defmodule Reef.FirstMate.Server do
  @moduledoc """
  Provides support to Reef.FirstMate.Server, specificially reef clean mode.
  """

  use GenServer, restart: :transient, shutdown: 7000
  use Helen.Module.Config

  alias Reef.DisplayTank.Ato

  ##
  ## GenServer Start and Initialization
  ##

  @doc false
  @impl true
  def init(args) do
    import Reef.FirstMate.Opts, only: [create_default_config_if_needed: 0]

    # just in case we were passed a map?!?
    args = Enum.into(args, [])

    create_default_config_if_needed()

    state = %{
      server_mode: args[:server_mode] || :active,
      server_standby_reason: :none,
      token: nil,
      token_at: nil,
      reef_mode: :ready,
      timeouts: %{last: :never, count: 0},
      opts: config_opts(args),
      delayed_cmd: %{}
    }

    # should the server start?
    cond do
      state[:server_mode] == :standby -> :ignore
      true -> {:ok, state, {:continue, :bootstrap}}
    end
  end

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ##
  ## Public API
  ##

  @doc """
  Is the server active?

  Returns a boolean.

  ## Examples

      iex> Reef.FirstMate.Server.active?
      true

  """
  @doc since: "0.0.27"
  def active? do
    case x_state() do
      %{server_mode: :standby, reef_mode: _} -> false
      %{server_mode: _, reef_mode: :not_ready} -> false
      _else -> true
    end
  end

  @doc """
  Bring all reef activities to a stop.

  Returns :ok

  ## Examples

      iex> Reef.FirstMate.Server.all_stop
      :ok

  """
  @doc since: "0.0.27"
  def all_stop, do: GenServer.call(__MODULE__, {:all_stop})

  @doc """
  Enable cleaning mode.

  Display tank ato is stopped for the configured clean duration.

  Required parameters:
    `mode:` <mode defined in config>
    `opts:` [] | <list to merge into config opts>

  Returns :ok.

  ## Examples

      iex> Reef.FirstMate.Server.mode(:clean, [])
      :ok

  """
  @doc since: "0.0.27"
  def mode(mode, opts), do: cast_if_valid_and_active(mode, opts)

  @doc """
  Return the DateTime of the last GenServer timeout.
  """
  @doc since: "0.0.27"
  def last_timeout do
    import Helen.Time.Helper, only: [epoch: 0, utc_now: 0]

    with last <- x_state(:last_timeout),
         d when d > 0 <- Timex.diff(last, epoch()) do
      Timex.to_datetime(last, "America/New_York")
    else
      _epoch -> epoch()
    end
  end

  @doc """
  Set the mode of the server.

  ## Modes
  When set to `:active` (normal mode) the server is ready for reef commands.

  If set to `:standby` the server will:
    1. Switch on the DisplayTank auto-top-off
    2. Denies all reef command mode requeests

  Returns {:ok, new_mode}

  ## Examples

      iex> Reef.FirstMate.Server(:standby)
      {:ok, :standby}

  """
  @doc since: "0.0.27"
  def server_mode(atom) when atom in [:active, :standby] do
    GenServer.call(__MODULE__, {:server_mode, atom})
  end

  @doc """
  Restarts the server via the Supervisor

  ## Examples

      iex> Reef.FirstMate.Server.restart([])
      :ok

  """
  @doc since: "0.0.27"
  def restart(opts \\ []) do
    # the Supervisor is the base of the module name with Supervisor appended
    [sup_base | _tail] = Module.split(__MODULE__)

    sup_mod = Module.concat([sup_base, "Supervisor"])

    if GenServer.whereis(__MODULE__) do
      Supervisor.terminate_child(sup_mod, __MODULE__)
    end

    Supervisor.delete_child(sup_mod, __MODULE__)
    Supervisor.start_child(sup_mod, {__MODULE__, opts})
  end

  @doc """
  Return the GenServer state.

  A single key (e.g. :server_mode) or a list of keys (e.g. :reef_mode, :server_mode)
  can be specified and only those keys are returned.
  """
  @doc since: "0.0.27"
  def x_state(keys \\ []) do
    import Helen.Time.Helper, only: [utc_now: 0]

    if is_nil(GenServer.whereis(__MODULE__)) do
      :DOWN
    else
      keys = [keys] |> List.flatten()

      state =
        GenServer.call(__MODULE__, :state)
        |> Map.drop([:opts])
        |> put_in([:state_at], utc_now())

      case keys do
        [] -> state
        [x] -> Map.get(state, x)
        x -> Map.take(state, [x] |> List.flatten())
      end
    end
  end

  @doc """
  Retrieve the number of GenServer timeouts that have occurred.
  """
  @doc since: "0.0.27"
  def timeouts, do: x_state() |> Map.get(:timeouts)

  ##
  ## GenServer handle_* callbacks
  ##

  @doc false
  @impl true
  def handle_call(:state, _from, state) do
    state = update_elapsed(state)
    reply(state, state)
  end

  @doc false
  @impl true
  def handle_call({:all_stop}, _from, state) do
    state
    |> all_stop__()
    |> reply(:answering_all_stop)
  end

  @doc false
  @impl true
  def handle_call({:server_mode, mode}, _from, state) do
    import Reef.Mode, only: [change_token: 1]

    case mode do
      # when switching to :standby ensure the switch is off
      :standby ->
        state
        |> change_token()
        |> crew_offline()
        |> put_in([:server_mode], mode)
        |> put_in([:server_standby_reason], :api)
        |> reply({:ok, mode})

      # no action when switching to :active, the server will take control
      :active ->
        state
        |> change_token()
        |> crew_online()
        |> put_in([:server_mode], mode)
        |> put_in([:server_standby_reason], :none)
        |> reply({:ok, mode})
    end
  end

  @doc false
  @impl true
  def handle_cast({:delayed_cmd, cmd, cmd_opts}, state) do
    import Helen.Time.Helper, only: [utc_now: 0]
    import Reef.Mode, only: [change_token: 1]

    # grab the requested delay and remove :start_delay from the opts
    {[{_, delay}], opts} = Keyword.split(cmd_opts, [:start_delay])

    msg = {:delayed_cmd, cmd, opts}

    state
    |> put_in([:delayed_cmd, :cmd], {cmd, cmd_opts})
    |> put_in([:delayed_cmd, :issued_at], utc_now())
    |> change_token_and_send_after(msg, delay)
    |> noreply()
  end

  @doc false
  @impl true
  # START A CASTED MODE
  def handle_cast({mode, cmd_opts}, %{opts: opts} = state) do
    import DeepMerge, only: [deep_merge: 2]
    import Reef.Mode, only: [start_mode: 2]

    cmd_opts = deep_merge(opts[mode], cmd_opts)

    state
    |> ensure_reef_mode_map(mode)
    |> put_in([mode, :status], :in_progress)
    |> put_in([mode, :steps], cmd_opts[:steps])
    |> put_in([mode, :sub_steps], cmd_opts[:sub_steps])
    |> put_in([mode, :step_devices], cmd_opts[:step_devices])
    |> put_in([mode, :opts], cmd_opts)
    |> start_mode(mode)
    |> noreply()
  end

  @doc false
  @impl true
  def handle_continue(:bootstrap, state) do
    import Reef.Mode, only: [change_token: 1]

    valid_opts? = validate_durations(state[:opts])

    case valid_opts? do
      true ->
        state
        |> change_token()
        |> crew_online()
        |> set_all_modes_ready()
        |> noreply()

      false ->
        state
        |> put_in([:reef_mode], :not_ready)
        |> put_in([:not_ready_reason], :invalid_opts)
        |> noreply()
    end
  end

  @doc false
  @impl true
  def handle_info(
        {:gen_device, %{token: msg_token, mod: mod, at: at, cmd: cmd}},
        %{
          reef_mode: reef_mode,
          token: token
        } = state
      )
      when msg_token == token do
    import Helen.Time.Helper, only: [utc_now: 0]
    import Reef.Mode, only: [start_next_cmd_in_step: 1, step_device_to_mod: 1]

    # for all messages we want capture when they were received and update
    # the elapsed time
    state =
      put_in(state, [reef_mode, :device_last_cmds, mod, cmd, at], utc_now())
      |> update_elapsed()

    # we only want to process :at_finish messages from step_devices
    # associated to steps and not sub steps
    active_step = get_in(state, [reef_mode, :active_step])

    expected_mod =
      get_in(state, [reef_mode, :step_devices, active_step])
      |> step_device_to_mod()

    if expected_mod == mod and at == :at_finish,
      do: state |> start_next_cmd_in_step() |> noreply(),
      else: state |> noreply()
  end

  @doc false
  @impl true
  # quietly drop gen_device messages that do not match the current token
  def handle_info(
        {:gen_device, %{token: msg_token}},
        %{token: token} = state
      )
      when msg_token != token,
      do: noreply(state)

  @doc false
  @impl true
  def handle_info({:gen_device, _payload} = msg, state) do
    msg_puts(msg, state)
  end

  @doc false
  @impl true
  # handle the case when the msg_token matches the current state.
  def handle_info({:timer, msg, msg_token}, %{token: token} = state)
      when msg_token == token do
    case msg do
      {:delayed_cmd, :clean, opts} ->
        GenServer.cast(__MODULE__, {:clean, opts})

        state
        |> put_in([:delayed_cmd], %{})
        |> noreply()

      _msg ->
        noreply(state)
    end
  end

  # NOTE:  when the msg_token does not match the state token then
  #        a change has occurred and this off message should be ignored
  def handle_info({:timer, msg, msg_token}, %{token: token} = state)
      when msg_token != token do
    case msg do
      {:delayed_cmd, _cmd} ->
        # if this was a delayed cmd message that failed the token match
        # then null out the delayed_cmd map
        state
        |> put_in([:delayed_cmd], %{})
        |> noreply()

      _no_match ->
        noreply(state)
    end
  end

  @doc false
  @impl true
  def handle_info(:timeout, state) do
    state
    |> update_last_timeout()
    |> timeout_hook()
  end

  @doc false
  @impl true
  def terminate(_reason, %{reef_mode: reef_mode} = state) do
    case reef_mode do
      _nomatch -> state
    end
  end

  ##
  ## PRIVATE
  ##

  defp all_stop__(state) do
    import Reef.Mode, only: [change_token: 1]

    state
    # prevent processing of any lingering messages
    |> change_token()
    # the safest way to stop everything is to take all the crew offline
    |> crew_offline()
    # bring them back online so they're ready for whatever comes next
    |> crew_online()
    |> set_all_modes_ready()
  end

  defp assemble_reef_mode_final_opts(reef_mode, overrides) do
    import DeepMerge, only: [deep_merge: 2]

    opts = [overrides] |> List.flatten()
    config_opts = config_opts([])

    deep_merge(get_in(config_opts, [reef_mode]), opts)
  end

  defp crew_list, do: [Ato]
  defp crew_list_no_heat, do: [Ato]

  # NOTE:  state is unchanged however is parameter for use in pipelines
  defp crew_offline(state) do
    for crew_member <- crew_list() do
      apply(crew_member, :mode, [:standby])
    end

    state
  end

  # NOTE:  state is unchanged however is parameter for use in pipelines
  defp crew_online(state) do
    # NOTE:  we NEVER bring MixTank.Temp online unless explictly requested
    #        in a mode step/cmd
    for crew_member <- crew_list_no_heat() do
      apply(crew_member, :mode, [:active])
    end

    state
  end

  def ensure_reef_mode_map(state, mode), do: state |> Map.put_new(mode, %{})

  defp msg_puts(msg, state) do
    """
     ==> #{inspect(msg)}

    """
    |> IO.puts()

    noreply(state)
  end

  defp update_elapsed(%{reef_mode: mode} = state) do
    import Helen.Time.Helper, only: [elapsed: 2, utc_now: 0]

    if get_in(state, [mode, :status]) do
      now = utc_now()
      started_at = get_in(state, [mode, :started_at])
      step_started_at = get_in(state, [mode, :step, :started_at])

      state
      |> put_in([mode, :elapsed], elapsed(started_at, now))
      |> put_in([mode, :step, :elapsed], elapsed(step_started_at, now))
    else
      state
    end
  end

  # primary entry point for validating durations
  defp validate_durations(opts) do
    # validate the opts with an initial accumulator of true so an empty
    # list is considered valid
    validate_duration_r(opts, true)
  end

  defp validate_duration_r(opts, acc) do
    import Helen.Time.Helper, only: [valid_ms?: 1]

    case {opts, acc} do
      # end of a list (or all list), simply return the acc
      {[], acc} ->
        acc

      # seen a bad duration, we're done
      {_, false} ->
        false

      # process the head (tuple) and the tail (a list or a tuple)
      {[head | tail], acc} ->
        acc && validate_duration_r(head, acc) &&
          validate_duration_r(tail, acc)

      # keep unfolding
      {{_, v}, acc} when is_list(v) ->
        acc && validate_duration_r(v, acc)

      # we have a tuple to check
      {{k, d}, acc} when k in [:run_for, :for] and is_binary(d) ->
        acc && valid_ms?(d)

      # not a tuple of interest, keep going
      {_no_interest, acc} ->
        acc
    end
  end

  ##
  ## GenServer Receive Loop Hooks
  ##

  defp timeout_hook(%{} = s) do
    noreply(s)
  end

  ##
  ## State Helpers
  ##

  defp change_token_and_send_after(state, msg, delay) do
    import Helen.Time.Helper, only: [to_ms: 1]
    import Reef.Mode, only: [change_token: 1]

    %{token: token} = state = change_token(state)

    Process.send_after(self(), {:timer, msg, token}, to_ms(delay))

    state
  end

  defp loop_timeout(%{opts: opts}) do
    import Helen.Time.Helper, only: [to_ms: 2]

    to_ms(opts[:timeout], "PT30.0S")
  end

  defp set_all_modes_ready(state) do
    modes = [
      :clean
    ]

    for m <- modes, reduce: state do
      state -> state |> put_in([m], %{status: :ready})
    end
    |> put_in([:reef_mode], :ready)
  end

  defp update_last_timeout(state) do
    import Helen.Time.Helper, only: [utc_now: 0]

    state
    |> put_in([:timeouts, :last], utc_now())
    |> update_in([:timeouts, :count], fn x -> x + 1 end)
  end

  ##
  ## GenServer.{call, cast} Helpers
  ##

  defp cast_if_valid_and_active(reef_mode, opts) do
    final_opts = assemble_reef_mode_final_opts(reef_mode, opts)

    valid? = validate_durations(final_opts)
    start_delay = opts[:start_delay]
    skip_active_check? = opts[:skip_active_check] || false
    reef_mode_exists? = get_in(final_opts, [:steps]) || false

    cond do
      valid? == false ->
        {reef_mode, :invalid_duration_opts, final_opts}

      is_nil(final_opts) ->
        {reef_mode, :opts_undefined, final_opts}

      reef_mode_exists? == false ->
        {reef_mode, :does_not_exist}

      is_binary(start_delay) ->
        if active?(),
          do: GenServer.cast(__MODULE__, {:delayed_cmd, reef_mode, final_opts})

      skip_active_check? ->
        GenServer.cast(__MODULE__, {reef_mode, final_opts})

      true ->
        if active?(),
          do: GenServer.cast(__MODULE__, {reef_mode, final_opts}),
          else: {:standby_mode}
    end
  end

  ##
  ## handle_* return helpers
  ##

  defp noreply(s), do: {:noreply, s, loop_timeout(s)}

  defp reply(s, val) when is_map(s), do: {:reply, val, s, loop_timeout(s)}
  defp reply(val, s), do: {:reply, val, s, loop_timeout(s)}
end
