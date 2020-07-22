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
    import Reef.FirstMate.Opts, only: [create_default_config_if_needed: 1]

    # just in case we were passed a map?!?
    args = Enum.into(args, [])

    create_default_config_if_needed(__MODULE__)

    state = %{
      module: __MODULE__,
      server_mode: args[:server_mode] || :active,
      worker_mode: :ready,
      server_standby_reason: :none,
      token: nil,
      token_at: nil,
      pending: %{},
      timeouts: %{last: :never, count: 0},
      opts: config_opts(args)
    }

    # should the server start?
    if state[:server_mode] == :standby,
      do: :ignore,
      else: {:ok, state, {:continue, :bootstrap}}
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
      %{server_mode: :standby, worker_mode: _} -> false
      %{server_mode: _, worker_mode: :not_ready} -> false
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
  def all_stop, do: call({:all_stop})

  @doc """
  Return a list of available reef modes.

  Returns a list.

  ## Examples

      iex> Reef.FirstMate.Server.available_modes()
      [:keep_fresh, :prep_for_change]

  """
  @doc since: "0.0.27"
  def available_modes, do: call({:available_modes})

  @doc """
  Set the FirstMate to a specific mode.
  """
  @doc since: "0.0.27"
  def worker_mode(mode, opts), do: call({:worker_mode, mode, opts})

  @doc since: "0.0.27"
  def cancel_delayed_cmd, do: call({:cancel_delayed_cmd})

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
  Return the server runtime options.
  """
  @doc since: "0.0.27"
  def runtime_opts do
    if is_nil(GenServer.whereis(__MODULE__)) do
      []
    else
      GenServer.call(__MODULE__, :state) |> get_in([:opts])
    end
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
  Set the mode of the server.

  ## Modes
  When set to `:active` (normal mode) the server is ready for reef commands.

  If set to `:standby` the server will:
    1. Take all crew members offline
    2. Denies all reef command mode requeests

  Returns {:ok, new_mode}

  ## Examples

      iex> Reef.Captain.Server(:standby)
      {:ok, :standby}

  """
  @doc since: "0.0.27"
  def server_mode(atom) when atom in [:active, :standby] do
    call({:server_mode, atom})
  end

  @doc """
  Return the GenServer state.

  A single key (e.g. :server_mode) or a list of keys (e.g. :worker_mode, :server_mode)
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
  def timeouts, do: x_state() |> get_in([:timeouts])

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
  def handle_call({:available_modes}, _from, state) do
    import Reef.Logic, only: [available_modes: 1]

    reply(state, state |> available_modes())
  end

  @doc false
  @impl true
  def handle_call({:cancel_delayed_cmd}, _from, state) do
    import Reef.Logic, only: [change_token: 1]

    timer = get_in(state, [:pending, :delayed])

    if is_reference(timer), do: Process.cancel_timer(timer)

    state
    |> put_in([:pending], %{})
    |> reply(:ok)
  end

  @doc false
  @impl true
  def handle_call({:server_mode, mode}, _from, state) do
    import Reef.Logic, only: [change_token: 1]

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
  def handle_call({:worker_mode, mode, api_opts}, _from, state) do
    # import Reef.Logic, only: [init_precheck: 3, init_mode: 1, start_mode: 1]

    state
    |> Reef.Logic.init_precheck(mode, api_opts)
    |> Reef.Logic.init_mode()
    |> Reef.Logic.start_mode()
    |> check_fault_and_reply()
  end

  @doc false
  @impl true
  def handle_call(msg, _from, state),
    do: state |> msg_puts(msg) |> reply({:unmatched})

  @doc false
  @impl true
  def handle_cast({:msg, {:handoff, worker_mode}}, state) do
    import Reef.Logic, only: [init_precheck: 3, init_mode: 1, start_mode: 1]

    state
    |> init_precheck(worker_mode, [])
    |> init_mode()
    |> start_mode()
    |> noreply()
  end

  @doc false
  @impl true
  def handle_cast({:msg, _cmd} = msg, state),
    do: state |> msg_puts(msg) |> noreply()

  @doc false
  @impl true
  def handle_continue(:bootstrap, state) do
    import Reef.Logic, only: [change_token: 1, validate_all_durations: 1]
    valid_opts? = state |> validate_all_durations()

    case valid_opts? do
      true ->
        state
        |> change_token()
        |> crew_online()
        |> set_all_modes_ready()
        |> noreply()

      false ->
        state
        |> put_in([:worker_mode], :not_ready)
        |> put_in([:not_ready_reason], :invalid_opts)
        |> noreply()
    end
  end

  @doc false
  @impl true
  def handle_info(
        {:gen_device, %{token: msg_token, mod: mod, at: at, cmd: cmd}},
        %{
          worker_mode: worker_mode,
          token: token
        } = state
      )
      when msg_token == token do
    import Helen.Time.Helper, only: [utc_now: 0]
    import Reef.Logic, only: [start_next_cmd_in_step: 1, step_device_to_mod: 1]

    # for all messages we want capture when they were received and update
    # the elapsed time
    state =
      put_in(state, [worker_mode, :device_last_cmds, mod, cmd, at], utc_now())
      |> update_elapsed()

    # we only want to process :at_finish messages from step_devices
    # associated to steps and not sub steps
    active_step = get_in(state, [worker_mode, :active_step])

    expected_mod =
      get_in(state, [worker_mode, :step_devices, active_step])
      |> step_device_to_mod()

    if expected_mod == mod and at == :at_finish,
      do: state |> start_next_cmd_in_step() |> noreply(),
      else: state |> noreply()
  end

  @doc false
  @impl true
  # quietly drop gen_device messages that do not match the current token
  def handle_info({:gen_device, %{token: msg_token}}, %{token: token} = state)
      when msg_token != token,
      do: noreply(state)

  @doc false
  @impl true
  def handle_info({:gen_device, _payload} = msg, state),
    do: state |> msg_puts(msg) |> noreply()

  @doc false
  @impl true
  def handle_info({:timer, :delayed_cmd}, state) do
    import Reef.Logic, only: [start_mode: 1]

    state
    |> update_in([:pending], fn x -> Map.drop(x, [:delay, :timer]) end)
    |> start_mode()
    |> noreply()
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
  def terminate(_reason, %{worker_mode: worker_mode} = state) do
    case worker_mode do
      _nomatch -> state
    end
  end

  ##
  ## PRIVATE
  ##

  defp all_stop__(state) do
    import Reef.Logic, only: [change_token: 1]

    state
    # prevent processing of any lingering messages
    |> change_token()
    # the safest way to stop everything is to take all the crew offline
    |> crew_offline()
    # bring them back online so they're ready for whatever comes next
    |> crew_online()
    |> set_all_modes_ready()
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

  def ensure_worker_mode_map(state, mode), do: state |> Map.put_new(mode, %{})

  defp msg_puts(state, msg) do
    """
     ==> #{inspect(msg)}

    """
    |> IO.puts()

    state
  end

  defp update_elapsed(%{worker_mode: mode} = state) do
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

  ##
  ## GenServer Receive Loop Hooks
  ##

  defp timeout_hook(state) do
    noreply(state)
  end

  ##
  ## State Helpers
  ##

  defp loop_timeout(%{opts: opts}) do
    import Helen.Time.Helper, only: [to_ms: 2]

    to_ms(opts[:timeout], "PT30.0S")
  end

  defp set_all_modes_ready(state) do
    import Reef.Logic, only: [available_modes: 1]

    for m <- available_modes(state), reduce: state do
      state -> state |> put_in([m], %{status: :ready})
    end
    |> put_in([:worker_mode], :ready)
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

  defp call(msg) do
    cond do
      server_down?() -> {:failed, :server_down}
      standby?() -> {:failed, :standby_mode}
      true -> GenServer.call(__MODULE__, msg)
    end
  end

  defp server_down? do
    GenServer.whereis(__MODULE__) |> is_nil()
  end

  defp standby? do
    case x_state() do
      %{server_mode: :standby} -> true
      %{server_mode: :active} -> false
      _state -> true
    end
  end

  ##
  ## handle_* return helpers
  ##

  defp check_fault_and_reply(%{fault: fault} = state) do
    {:reply, {:fault, fault}, state, loop_timeout(state)}
  end

  defp check_fault_and_reply(%{worker_mode: worker_mode} = state) do
    {:reply, {:ok, worker_mode}, state, loop_timeout(state)}
  end

  defp noreply(s), do: {:noreply, s, loop_timeout(s)}

  defp reply(s, val) when is_map(s), do: {:reply, val, s, loop_timeout(s)}
  defp reply(val, s), do: {:reply, val, s, loop_timeout(s)}
end
