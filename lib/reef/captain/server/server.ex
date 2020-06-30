defmodule Reef.Captain.Server do
  @moduledoc """
  Orchestration of Reef Activities (e.g. salt mix, cleaning)
  """

  use GenServer, restart: :transient, shutdown: 7000
  use Helen.Module.Config

  alias Reef.DisplayTank.Ato
  alias Reef.MixTank.{Air, Pump, Rodi}

  ##
  ## GenServer Start and Initialization
  ##

  @doc false
  @impl true
  def init(args) do
    import Helen.Time.Helper, only: [epoch: 0, zero: 0]

    # just in case we were passed a map?!?
    args = Enum.into(args, [])

    state =
      %{
        server_mode: args[:server_mode] || :active,
        token: 1,
        reef_mode: :ready,
        timeouts: 0,
        last_timeout: epoch(),
        opts: config_opts(args),
        standby_reason: :none,
        delayed_cmd: %{}
      }
      |> set_all_modes_ready()

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

      iex> Reef.Temp.Control.active?
      true

  """
  @doc since: "0.0.27"
  def active? do
    case state([:server_mode, :reef_mode]) do
      %{active: _, reef_mode: :not_ready} -> false
      %{active: :standby, reef_mode: _} -> false
      _else -> true
    end
  end

  @doc """
  Bring all reef activities to a stop.

  Returns :ok

  ## Examples

      iex> Reef.Captain.Server.all_stop
      :ok

  """
  @doc since: "0.0.27"
  def all_stop, do: GenServer.call(__MODULE__, {:all_stop})

  @doc """
  Enable cleaning mode.

  Display tank ato is stopped for the configured clean duration.

  If unconfigured the default is [hours: 2]

  Returns :ok.

  ## Examples

      iex> Reef.Captain.Server.clean()
      :ok

  """
  @doc since: "0.0.27"
  def clean, do: call_if_active({:clean})

  @doc """
  Fill the MixTank with RODI.

  Returns `:ok`, `{:not_configured, opts}` or `{:invalid_duration_opts}`

  ## Examples

      iex> Reef.Captain.Server.fill()
      :ok

  """
  @doc since: "0.0.27"
  def fill(opts), do: cast_if_valid_and_active(:fill, opts)

  @doc """
  Keep the MixTank fresh by aerating and circulating the water.

  Returns `:ok`, `{:not_configured, opts}` or `{:invalid_duration_opts}`

  ## Examples

      iex> Reef.Captain.Server.keep_fresh()
      :ok

  ### Example Options
    `start_delay: "PT5M30S"` delay the start of this command by 1 min 30 secs

  """
  @doc since: "0.0.27"
  def keep_fresh(opts), do: cast_if_valid_and_active(:keep_fresh, opts)

  def last_timeout do
    import Helen.Time.Helper, only: [epoch: 0, utc_now: 0]

    with last <- state(:last_timeout),
         d when d > 0 <- Timex.diff(last, epoch()) do
      Timex.to_datetime(last, "America/New_York")
    else
      _epoch -> epoch()
    end
  end

  @doc """
  Runs the necessary components to mix salt into the MixTank.

  Returns `:ok`, `{:not_configured, opts}` or `{:invalid_duration_opts}`

  ## Examples

      iex> Reef.Captain.Server.mix_salt()
      :ok

  ### Example Options
    `start_delay: "PT5M30S"` delay the start of this command by 1 min 30 secs

  """
  @doc since: "0.0.27"
  def mix_salt(opts), do: cast_if_valid_and_active(:mix_salt, opts)

  @doc """
  Set the mode of the server.

  ## Modes
  When set to `:active` (normal mode) the server will actively control
  the temperature based on the readings of the configured sensor by
  turning on and off the switch.

  If set to `:standby` the server will:
    1. Ensure the switch if off
    2. Continue to receive updates from sensors and switches
    3. Will *not* attempt to control the temperature.

  Returns {:ok, new_mode}

  ## Examples

      iex> Reef.Temp.Control.mode(:standby)
      {:ok, :standby}

  """
  @doc since: "0.0.27"
  def mode(atom) when atom in [:active, :standby] do
    GenServer.call(__MODULE__, {:server_mode, atom})
  end

  @doc """
  Restarts the server via the Supervisor

  ## Examples

      iex> Reef.Temp.Control.restart([])
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

  def state(keys \\ []) do
    if is_nil(GenServer.whereis(__MODULE__)) do
      :DOWN
    else
      keys = [keys] |> List.flatten()

      state = GenServer.call(__MODULE__, :state)

      case keys do
        [] -> state
        [x] -> Map.get(state, x)
        x -> Map.take(state, [x] |> List.flatten())
      end
    end
  end

  def timeouts, do: state() |> Map.get(:timeouts)

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
  def handle_call({:all_stop}, _from, %{opts: _opts} = state) do
    state
    |> all_stop()
    |> reply(:answering_all_stop)
  end

  @doc false
  @impl true
  def handle_call({:clean}, _from, %{opts: opts} = state) do
    [{cmd, cmd_opts}] = opts[:clean]

    # NOTE:  if a clean cycle is already in progress the call
    #        to Ato will invalidate it's timer so the previous
    #        clean cycle is effectively canceled
    apply_cmd(cmd, Ato, add_notify_opts(cmd_opts))

    state
    # clear out the previous clean cycle, if any
    |> put_in([:clean], %{})
    |> put_in([:clean, :status], :requested)
    |> put_in([:clean, :opts], opts[:clean])
    |> reply(:ok)
  end

  @doc false
  @impl true
  def handle_cast({:delayed_cmd, cmd, cmd_opts}, state) do
    import Helen.Time.Helper, only: [utc_now: 0]

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
  def handle_cast({:fill, cmd_opts}, %{opts: opts} = state) do
    import DeepMerge, only: [deep_merge: 2]

    cmd_opts = deep_merge(opts[:fill], cmd_opts)

    state
    |> put_in([:fill, :status], :in_progress)
    |> put_in([:fill, :steps], cmd_opts[:steps])
    |> put_in([:fill, :sub_steps], cmd_opts[:sub_steps])
    |> put_in([:fill, :steps_to_execute], Keyword.keys(cmd_opts[:steps]))
    |> put_in([:fill, :step_devices], cmd_opts[:step_devices])
    |> put_in([:fill, :opts], cmd_opts)
    |> start_mode(:fill)
    |> noreply()
  end

  @doc false
  @impl true
  def handle_cast({:keep_fresh, cmd_opts}, %{opts: opts} = state) do
    import DeepMerge, only: [deep_merge: 2]

    cmd_opts = deep_merge(opts[:keep_fresh], cmd_opts)

    state
    |> put_in([:keep_fresh, :status], :running)
    |> put_in([:keep_fresh, :steps], cmd_opts[:steps])
    |> put_in([:keep_fresh, :sub_steps], cmd_opts[:sub_steps])
    |> put_in([:keep_fresh, :step_devices], cmd_opts[:step_devices])
    |> put_in([:keep_fresh, :opts], cmd_opts)
    |> start_mode(:keep_fresh)
    |> noreply()
  end

  @doc false
  @impl true
  def handle_cast({:mix_salt, cmd_opts}, %{opts: opts} = state) do
    import DeepMerge, only: [deep_merge: 2]

    cmd_opts = deep_merge(opts[:mix_salt], cmd_opts)

    state
    |> put_in([:mix_salt, :status], :in_progress)
    |> put_in([:mix_salt, :steps], cmd_opts[:steps])
    |> put_in([:mix_salt, :sub_steps], cmd_opts[:sub_steps])
    |> put_in([:mix_salt, :step_devices], cmd_opts[:step_devices])
    |> put_in([:mix_salt, :opts], cmd_opts)
    |> start_mode(:mix_salt)
    |> noreply()
  end

  @doc false
  @impl true
  def handle_cast({:msg, msg}, state) do
    case msg do
      {:handoff, :keep_fresh} ->
        keep_fresh(skip_active_check: true)
        noreply(state)

      {:handoff, :prep_for_change} ->
        state |> change_token() |> noreply()

      msg ->
        msg_puts(msg, state)
    end
  end

  @doc false
  @impl true
  def handle_continue(:bootstrap, state) do
    valid_opts? = validate_durations(state[:opts])

    case valid_opts? do
      true ->
        noreply(state)

      false ->
        state
        |> put_in([:reef_mode], :not_ready)
        |> put_in([:not_ready_reason], :invalid_opts)
        |> noreply()
    end
  end

  @doc false
  @impl true
  def handle_info({:gen_device, %{at: at_phase, cmd: :off, mod: Ato}}, state) do
    import Helen.Time.Helper, only: [utc_now: 0, elapsed: 2]

    case at_phase do
      :at_start ->
        state
        |> put_in([:clean, :started_at], utc_now())
        |> put_in([:clean, :ato_rc], Ato.value())
        |> put_in([:clean, :status], :active)
        |> noreply()

      :at_finish ->
        now = utc_now()
        started_at = state[:clean][:started_at]

        state
        |> put_in([:clean, :finished_at], now)
        |> put_in([:clean, :ato_rc], Ato.value())
        |> put_in([:clean, :status], :complete)
        |> put_in([:clean, :elapsed], elapsed(started_at, now))
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
      {:delayed_cmd, :fill, opts} ->
        GenServer.cast(__MODULE__, {:fill, opts})

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
      :keep_fresh -> state |> all_stop()
    end
  end

  ##
  ## PRIVATE
  ##

  defp add_notify_opts(opts),
    do: [opts, notify: [:at_start, :at_finish]] |> List.flatten()

  defp add_notify_opts_include_token(%{token: t}, opts),
    do: [opts, notify: [:at_start, :at_finish, token: t]] |> List.flatten()

  defp apply_cmd(state, dev, cmd, opts)
       when dev in [:air, :pump, :rodi] and cmd in [:on, :off] do
    cmd_opts = add_notify_opts_include_token(state, opts)

    apply(step_device_to_mod(dev), cmd, [cmd_opts])
  end

  # TODO eliminate this function
  defp apply_cmd(cmd, mod, opts) do
    case cmd do
      :on -> apply(mod, cmd, [opts])
      :off -> apply(mod, cmd, [opts])
    end
  end

  defp all_stop(state) do
    for c <- crew_list() do
      apply(c, :mode, [:standby])
    end

    state
    |> change_token()
    |> set_all_modes_ready()
  end

  defp step_device_to_mod(dev) do
    case dev do
      :air -> Air
      :pump -> Pump
      :rodi -> Rodi
    end
  end

  defp call_if_active(msg) do
    if active?(), do: GenServer.call(__MODULE__, msg), else: {:standby_mode}
  end

  defp cast_if_valid_and_active(reef_mode, opts) do
    import DeepMerge, only: [deep_merge: 2]

    opts = [opts] |> List.flatten()
    config_opts = config_opts([])

    final_opts = deep_merge(get_in(config_opts, [reef_mode]), opts)

    valid? = validate_durations(final_opts)
    start_delay = opts[:start_delay]
    skip_active_check? = opts[:skip_active_check] || false

    final_opts = Keyword.drop(final_opts, [:skip_active_check])

    cond do
      valid? == false ->
        {reef_mode, :invalid_duration_opts, final_opts}

      is_nil(final_opts) ->
        {reef_mode, :opts_undefined, final_opts}

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

  defp change_reef_mode(%{reef_mode: old_reef_mode} = state, new_reef_mode) do
    update_running_mode_status = fn
      x, :keep_fresh ->
        import Helen.Time.Helper, only: [utc_now: 0]

        put_in(x, [:keep_fresh, :status], :completed)
        |> put_in([:keep_fresh, :finished_at], utc_now())

      x, _anything ->
        x
    end

    update_running_mode_status.(state, old_reef_mode)
    |> put_in([:reef_mode], new_reef_mode)
    |> change_token()
  end

  defp config_device_to_mod(atom) when atom in [:air, :pump, :rodi, :heat] do
    alias Reef.MixTank.{Air, Pump, Rodi}
    alias Reef.MixTank.Temp, as: Heat

    case atom do
      :air -> Air
      :pump -> Pump
      :rodi -> Rodi
      :heat -> Heat
    end
  end

  defp crew_list, do: [Air, Pump, Rodi]

  defp msg_puts(msg, state) do
    """
     ==> #{inspect(msg)}

    """
    |> IO.puts()

    noreply(state)
  end

  defp finish_mode(%{reef_mode: mode} = state) do
    import Helen.Time.Helper, only: [elapsed: 2, utc_now: 0]

    # record the mode execution metrics
    started_at = get_in(state, [mode, :started_at])
    now = utc_now()

    state
    |> put_in([mode, :status], :completed)
    |> put_in([mode, :finished_at], now)
    |> put_in([mode, :elapsed], elapsed(started_at, now))
    |> put_in([:reef_mode], :ready)
  end

  ##
  ## ENTRY POINT FOR STARTING A REEF MODE
  ##  ** only called once per reef mode change
  ##
  defp start_mode(state, reef_mode) do
    import Helen.Time.Helper, only: [utc_now: 0]

    # local function to build the device last cmds map for each device
    device_last_cmds =
      for {_k, v} <- get_in(state, [reef_mode, :step_devices]) || [],
          into: %{} do
        map = %{
          off: %{at_finish: nil, at_start: nil},
          on: %{at_finish: nil, at_start: nil}
        }

        {config_device_to_mod(v), map}
      end

    steps = get_in(state, [reef_mode, :steps])

    change_reef_mode(state, reef_mode)
    |> calculate_will_finish_by_if_needed()
    # mode -> :device_last_cmds is 'global' for the mode and not specific
    # to a single step or command
    |> put_in([reef_mode, :steps_to_execute], Keyword.keys(steps))
    |> put_in([reef_mode, :started_at], utc_now())
    |> put_in([reef_mode, :device_last_cmds], device_last_cmds)
    |> put_in([reef_mode, :step], %{})
    |> put_in([reef_mode, :cycles], %{})
    |> start_mode_next_step()
  end

  defp start_mode_next_step(%{reef_mode: reef_mode} = state) do
    import Helen.Time.Helper, only: [utc_now: 0]

    # the next step is always the head of :steps_to_execute
    steps_to_execute = get_in(state, [reef_mode, :steps_to_execute])
    # NOTE:  each clause returns the state, even if unchanged
    cond do
      steps_to_execute == [] ->
        # we've reached the end of this mode!
        state
        |> finish_mode()

      true ->
        next_step = steps_to_execute |> hd()

        cmds = get_in(state, [reef_mode, :steps, next_step])

        state
        # remove the step we're starting
        |> update_in([reef_mode, :steps_to_execute], fn x -> tl(x) end)
        |> put_in([reef_mode, :active_step], next_step)
        # the reef_mode step key contains the control map for the step executing
        |> put_in([reef_mode, :step, :started_at], utc_now())
        |> put_in([reef_mode, :step, :elapsed], 0)
        |> put_in([reef_mode, :step, :run_for], nil)
        |> put_in([reef_mode, :step, :repeat?], nil)
        |> put_in([reef_mode, :step, :cmds_to_execute], cmds)
        |> update_step_cycles()
        |> start_next_cmd_in_step()
    end
  end

  defp start_next_cmd_in_step(%{reef_mode: mode} = state) do
    import Helen.Time.Helper, only: [elapsed?: 2, subtract_list: 1, utc_now: 0]

    active_step = get_in(state, [mode, :active_step])
    cmds_to_execute = get_in(state, [mode, :step, :cmds_to_execute])

    repeat? = get_in(state, [mode, :step, :repeat?]) || false
    run_for = get_in(state, [mode, :step, :run_for])

    # NOTE:  each clause returns the state, even if unchanged
    cond do
      cmds_to_execute == [] and repeat? == true ->
        # when repeating populate the steps to execute with this step
        # at the head of the list and call start_mode_next_step
        steps_to_execute =
          [active_step, get_in(state, [mode, :steps_to_execute])]
          |> List.flatten()

        state
        |> put_in([mode, :steps_to_execute], steps_to_execute)
        |> start_mode_next_step()

      cmds_to_execute == [] ->
        # we've reached the end of this step, start the next one
        state
        |> start_mode_next_step()

      is_binary(run_for) ->
        started_at = get_in(state, [mode, :step, :started_at]) || utc_now()

        # to prevent exceeding the configured run_for include the duration of the
        # step about to start in the elapsed?
        steps = get_in(state, [mode, :steps])
        on_for = get_in(steps, [active_step, :on, :for])
        off_for = get_in(steps, [active_step, :off, :for])

        # NOTE:  this design decision may result in the fill running for less
        #        time then the run_for configuration when the duration of the steps
        #        do not fit evenly
        calculated_run_for = subtract_list([run_for, on_for, off_for])

        if elapsed?(started_at, calculated_run_for) do
          # run_for has elapsed, move on to the next step
          state |> start_mode_next_step()
        else
          # there is still time in this step, run the command
          state |> start_next_cmd_and_pop()
        end

      true ->
        state |> start_next_cmd_and_pop()
    end
  end

  defp start_next_cmd_and_pop(%{reef_mode: mode} = state) do
    next_cmd = get_in(state, [mode, :step, :cmds_to_execute]) |> hd()

    put_in(state, [mode, :step, :next_cmd], next_cmd)
    |> update_in([mode, :step, :cmds_to_execute], fn x -> tl(x) end)
    |> start_next_cmd()
  end

  defp start_next_cmd(%{reef_mode: mode} = state) do
    # example:  state -> keep_fresh -> aerate

    active_step = get_in(state, [mode, :active_step])
    next_cmd = get_in(state, [mode, :step, :next_cmd])

    case next_cmd do
      {:run_for, duration} ->
        # consume the run_for command by putting it in the step control map
        # then call start_next_cmd/1
        state
        |> put_in([mode, :step, :run_for], duration)
        |> start_next_cmd_in_step()

      {:repeat, true} ->
        # consume the repeat command by putting it in the step control map
        # then call start_next_cmd/1
        state
        |> put_in([mode, :step, :repeat?], true)
        |> start_next_cmd_in_step()

      {:msg, _} = msg ->
        GenServer.cast(__MODULE__, msg)
        state |> start_mode_next_step()

      # this is an actual command to start
      {cmd, cmd_opts} when is_list(cmd_opts) and cmd in [:on, :off] ->
        dev = get_in(state, [mode, :step_devices, active_step])

        apply_cmd(state, dev, cmd, cmd_opts)

        state |> put_in([mode, :step, :cmd], cmd)

      # this is a reference to another step cmd
      # execute the referenced step/cmd
      {step_ref, cmd} when is_atom(cmd) ->
        # steps to execute and call ourself again
        dev = get_in(state, [mode, :step_devices, step_ref])
        cmd_opts = get_in(state, [mode, :sub_steps, step_ref, cmd])
        apply_cmd(state, dev, cmd, cmd_opts)

        state |> start_next_cmd_in_step()
    end
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

      {[{_k, list} | _rest], acc} when is_list(list) ->
        validate_duration_r(list, acc)

      # look at the head of the list, when it's key of interest
      # validate it can be converted to milliseconds and recurse
      # the tail
      {[{k, v} | rest], acc} when k in [:run_for, :for] ->
        validate_duration_r(rest, acc and valid_ms?(v))

      # not a keyword or other term (e.g. atom) of interest, keep going
      {_, acc} ->
        acc
    end
  end

  defp calculate_will_finish_by_if_needed(%{reef_mode: reef_mode} = state) do
    import Helen.Time.Helper, only: [to_ms: 1, utc_shift: 1]

    # grab the list of steps to avoid redundant traversals
    steps = get_in(state, [reef_mode, :steps])

    # will_finish_by can not be calculated if the reef mode
    # contains the cmd repeat: true
    has_repeat? =
      for {_name, cmds} <- steps, {:repeat, true} <- cmds, reduce: false do
        _acc -> true
      end

    if has_repeat? == true do
      state
    else
      # unfold each step in the steps list matching on the key :run_for.
      # convert each value to ms and reduce with a start value of 0.
      will_finish_by =
        for {_step, details} <- get_in(state, [reef_mode, :steps]),
            {k, run_for} when k == :run_for <- details,
            reduce: 0 do
          total_ms -> total_ms + to_ms(run_for)
        end
        |> utc_shift()

      state |> put_in([reef_mode, :will_finish_by], will_finish_by)
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

  defp change_token(%{} = s), do: update_in(s, [:token], fn x -> x + 1 end)

  defp change_token_and_send_after(state, msg, delay) do
    import Helen.Time.Helper, only: [to_ms: 1]

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
      :clean,
      :fill,
      :keep_fresh,
      :mix_salt,
      :prep_for_change,
      :transfer_h2o,
      :finalize_change
    ]

    for m <- modes, reduce: state do
      state -> state |> put_in([m], %{status: :ready})
    end
    |> put_in([:reef_mode], :ready)
  end

  defp update_step_cycles(%{reef_mode: mode} = state) do
    active_step = get_in(state, [mode, :active_step])

    update_in(state, [mode, :cycles, active_step], fn
      nil -> 1
      x -> x + 1
    end)
  end

  defp update_last_timeout(s) do
    import Helen.Time.Helper, only: [utc_now: 0]

    put_in(s, [:last_timeout], utc_now())
    |> Map.update(:timeouts, 1, &(&1 + 1))
  end

  ##
  ## handle_* return helpers
  ##

  defp noreply(s), do: {:noreply, s, loop_timeout(s)}

  defp reply(s, val) when is_map(s), do: {:reply, val, s, loop_timeout(s)}
  defp reply(val, s), do: {:reply, val, s, loop_timeout(s)}
end
