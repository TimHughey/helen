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
  def fill(opts) do
    import DeepMerge, only: [deep_merge: 2]

    # opts specified here are automatically placed under the :fill key
    # so they can be succesfully merged with the overall opts
    opts = [opts] |> List.flatten()
    config_opts = config_opts([])

    final_opts = deep_merge(config_opts[:fill], opts)
    valid? = validate_durations(final_opts)
    start_delay = opts[:start_delay]

    cond do
      valid? == false ->
        {:invalid_duration_opts, final_opts}

      is_nil(final_opts) ->
        {:fill_opts_undefined, final_opts}

      is_binary(start_delay) ->
        cast_if_active({:delayed_cmd, :fill, final_opts})

      true ->
        cast_if_active({:fill, final_opts})
    end
  end

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
  def keep_fresh(opts) do
    import DeepMerge, only: [deep_merge: 2]
    # opts specified here are automatically placed under the :fill key
    # so they can be succesfully merged with the overall opts
    opts = [opts] |> List.flatten()
    config_opts = config_opts([])

    final_opts = deep_merge(config_opts[:keep_fresh], opts)
    valid? = validate_durations(final_opts)
    start_delay = opts[:start_delay]

    cond do
      valid? == false ->
        {:keep_fresh, :invalid_duration_opts, final_opts}

      is_nil(final_opts) ->
        {:keep_fresh, :opts_undefined, final_opts}

      is_binary(start_delay) ->
        cast_if_active({:delayed_cmd, :keep_fresh, final_opts})

      true ->
        cast_if_active({:keep_fresh, final_opts})
    end
  end

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
    for c <- crew_list() do
      apply(c, :mode, [:standby])
    end

    change_token(state)
    |> set_all_modes_ready()
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
  def handle_cast({:fill, fill_opts}, state) do
    import Helen.Time.Helper, only: [utc_now: 0, utc_shift: 1]

    filtered_steps = fn opts ->
      case get_in(opts, [:steps_to_execute]) do
        nil ->
          {opts[:steps], Keyword.keys(opts[:steps])}

        # steps to execute specified in opts, however filter
        # the list by the steps available
        x ->
          steps = Keyword.take(opts[:steps], x)
          {steps, Keyword.keys(steps)}
      end
    end

    {steps, to_execute} = filtered_steps.(fill_opts)

    fill = %{
      status: :in_progress,
      steps: steps,
      steps_to_execute: to_execute,
      active_step: hd(to_execute),
      step: %{},
      started_at: utc_now(),
      will_finish_ms: will_finish_by_ms(steps),
      will_finish_by: utc_shift(will_finish_by_ms(steps)),
      finished_at: nil,
      elapsed: 0,
      opts: fill_opts
    }

    state
    |> change_reef_mode(:fill)
    |> put_in([:fill], fill)
    |> fill_start_active_step()
    |> noreply()
  end

  @doc false
  @impl true
  def handle_cast({:keep_fresh, cmd_opts}, %{opts: opts} = state) do
    import DeepMerge, only: [deep_merge: 2]

    cmd_opts = deep_merge(opts[:keep_fresh], cmd_opts)
    steps = cmd_opts[:steps]

    keep = %{
      status: :running,
      leader: cmd_opts[:leader],
      steps: cmd_opts[:steps],
      sub_steps: cmd_opts[:sub_steps],
      steps_to_execute: Keyword.keys(steps),
      step_devices: cmd_opts[:step_devices],
      opts: cmd_opts
    }

    state
    |> put_in([:keep_fresh], keep)
    |> reef_mode_start(:keep_fresh)
    |> noreply()
  end

  @doc false
  @impl true
  def handle_cast({:handoff, _cmd} = msg, state) do
    case msg do
      {:handoff, :keep_fresh = cmd} ->
        GenServer.cast(__MODULE__, {cmd, []})
        noreply(state)

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
  # FILL MODE
  def handle_info(
        {:gen_device, %{mod: Rodi} = msg},
        %{
          reef_mode: :fill,
          fill: %{
            active_step: step,
            steps: steps
          }
        } = state
      ) do
    import Helen.Time.Helper, only: [scale: 2, to_duration: 1, utc_now: 0]

    case msg do
      %{at: :at_start, cmd: cmd} when cmd in [:on, :off] ->
        # for :at_start we only want to record the executing cmd
        state
        |> put_in([:fill, :step, :cmd], cmd)
        |> noreply()

      %{at: :at_finish, cmd: :on} ->
        # for :at_finish and :on we want to start off and update :active_cmd
        # to pattern match

        # NOTE:  we do not check the elapsed step time against :run_for
        #        :at_finish, :on.  this purposeful as we never want to
        #        end a step with Rodi on for :fill
        get_in(steps, [step, :off]) |> add_notify_opts() |> Rodi.off()

        air_run_for =
          get_in(steps, [step, :off, :for]) |> to_duration() |> scale(0.25)

        Air.on(for: air_run_for, at_cmd_finish: :off)

        state
        |> put_in([:fill, :cmd], :off)
        |> noreply()

      %{at: :at_finish, cmd: :off} ->
        # for :at_finish and :off we have finished a cycle of this step
        # NOTE:  we rely on fill_start_active_step to decide if another cycle
        #        of the current step is necessary (based on :run_for) or if the
        #        next step should be executed,
        #
        state
        |> fill_start_active_step()
        |> noreply()
    end
  end

  @doc false
  @impl true
  def handle_info(
        {:gen_device, %{token: msg_token, mod: mod, at: at, cmd: cmd} = msg},
        %{
          reef_mode: reef_mode,
          token: token
        } = state
      )
      when reef_mode == :keep_fresh and msg_token == token do
    import Helen.Time.Helper, only: [utc_now: 0]

    active_step = get_in(state, [reef_mode, :active_step])

    # for all messages we want capture when they were received and update
    # the elapsed time
    state =
      put_in(
        state,
        [reef_mode, :step, :device_last_cmds, mod, cmd, at],
        utc_now()
      )
      |> update_elapsed()

    # for the keep fresh implementation we rely on the :at_finish messages
    # from Air to move us forward in the list of cmds
    case msg do
      %{mod: Air, at: :at_finish} ->
        start_next_cmd_in_step(state, active_step) |> noreply()

      _msg ->
        state |> noreply
    end
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
  def handle_info({:gen_device, _payload} = msg, state),
    do: msg_puts(msg, state)

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

  ##
  ## PRIVATE
  ##

  defp add_notify_opts(opts),
    do: [opts, notify: [:at_start, :at_finish]] |> List.flatten()

  defp add_notify_opts_include_token(%{token: t}, opts),
    do: [opts, notify: [:at_start, :at_finish, token: t]] |> List.flatten()

  defp apply_cmd(state, mod, cmd, opts)
       when mod in [:air, :pump] and cmd in [:on, :off] do
    atom_to_mod = fn
      :air -> Air
      :pump -> Pump
    end

    cmd_opts = add_notify_opts_include_token(state, opts)

    apply(atom_to_mod.(mod), cmd, [cmd_opts])
  end

  # TODO eliminate this function
  defp apply_cmd(cmd, mod, opts) do
    case cmd do
      :on -> apply(mod, cmd, [opts])
      :off -> apply(mod, cmd, [opts])
    end
  end

  defp call_if_active(msg) do
    if active?(), do: GenServer.call(__MODULE__, msg), else: {:standby_mode}
  end

  defp cast_if_active(msg) do
    if active?(), do: GenServer.cast(__MODULE__, msg), else: {:standby_mode}
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

  defp fill_finally(%{fill: %{steps: steps}} = state) do
    import Helen.Time.Helper, only: [elapsed: 2, elapsed?: 2, utc_now: 0]

    # :finally is a "reserved keyword" and requires special handling as it
    # is not a typical fill step but rather an instruction of what to
    # do when all steps complete

    GenServer.cast(__MODULE__, get_in(steps, [:finally, :msg]))

    # :finally is also the last step and, as such, signals the end of
    # the fill command.  record finished_at and calculate the
    # elapsed duration and note fill is completed.
    now = utc_now()
    started_at = get_in(state, [:fill, :started_at])

    # NOTE: we return the updated step, with fill containing only relevant keys
    state
    |> update_in([:fill], fn x -> Map.take(x, [:started_at]) end)
    |> put_in([:fill, :finished_at], now)
    |> put_in([:fill, :elapsed], elapsed(started_at, now))
    |> put_in([:fill, :status], :completed)
  end

  defp fill_start_active_step(%{fill: %{active_step: a, steps: s}} = state)
       when a == :finally or s == [],
       do: fill_finally(state)

  defp fill_start_active_step(state), do: fill_start_next_step_if_needed(state)

  defp fill_start_next_step_if_needed(
         %{fill: %{active_step: active_step, steps: steps}} = state
       ) do
    import Helen.Time.Helper,
      only: [subtract_list: 1, elapsed: 2, elapsed?: 2, utc_now: 0]

    # each step contains a :run_for key that defines how long the
    # step will will cycle on and off
    started_at = get_in(state, [:fill, :step, :started_at]) || utc_now()

    # to prevent exceeding the configured run_for include the duration of the
    # step about to start in the elapsed?
    config_run_for = get_in(steps, [active_step, :run_for])
    on_for = get_in(steps, [active_step, :on, :for])
    off_for = get_in(steps, [active_step, :off, :for])

    # NOTE:  this design decision may result in the fill running for less
    #        time then the run_for configuration when the duration of the steps
    #        do not fit evenly
    run_for = subtract_list([config_run_for, on_for, off_for])

    case elapsed?(started_at, run_for) do
      false ->
        # run_for has not elapsed so turn on Rodi.
        # NOTE:  we always turn on Rodi when starting a step even if :on is not
        #        listed first.  this is a design decision and design constraint
        Air.off()
        get_in(steps, [active_step, :on]) |> add_notify_opts() |> Rodi.on()

        state
        |> put_in([:fill, :step, :started_at], started_at)
        |> put_in([:fill, :step, :elapsed], elapsed(started_at, utc_now()))
        |> update_reef_mode_cycles()

      true ->
        import List, only: [delete_at: 2]

        # run_for has elapsed, remove the current active step from
        # steps_to_execute, clear out the step tracked (:step) then call
        # this function again to start the next step
        state
        # set the active step to the next one in the list of steps to execute
        |> put_in(
          [:fill, :active_step],
          get_in(state, [:fill, :steps_to_execute]) |> hd()
        )
        # remove the step just completed
        |> update_in([:fill, :steps_to_execute], fn x -> delete_at(x, 0) end)
        # a new step is about to begin, reset the step control map
        |> put_in([:fill, :step], %{cmd: :none})
        # call fill_start_active_step
        |> fill_start_active_step()
    end
  end

  defp msg_puts(msg, state) do
    """
     ==> #{inspect(msg)}

    """
    |> IO.puts()

    noreply(state)
  end

  defp reef_mode_complete(%{reef_mode: mode} = state) do
    import Helen.Time.Helper, only: [elapsed: 2, utc_now: 0]

    # is there a finally step we need to handle?
    case get_in(state, [mode, :steps, :finally]) do
      x when is_nil(x) -> nil
      [{:msg, _payload} = msg] -> GenServer.cast(__MODULE__, msg)
      finally -> IO.puts(["unhandled #{inspect(finally)}"])
    end

    # record the mode execution metrics
    started_at = get_in(state, [mode, :started_at])
    now = utc_now()

    state
    |> put_in([mode, :status], :complete)
    |> put_in([mode, :finished_at], now)
    |> put_in([mode, :elapsed], elapsed(started_at, now))
    |> put_in([:reef_mode], :ready)
  end

  defp reef_mode_start(state, reef_mode) do
    import Helen.Time.Helper, only: [utc_now: 0]

    mode_map = get_in(state, [reef_mode])
    start_with = mode_map[:leader] || mode_map[:steps] |> Keyword.keys() |> hd()
    cmds = get_in(mode_map, [:steps, start_with])

    device_last_cmds =
      for {_k, v} <- mode_map[:step_devices] || [], into: %{} do
        map = %{
          off: %{at_finish: nil, at_start: nil},
          on: %{at_finish: nil, at_start: nil}
        }

        {config_device_to_mod(v), map}
      end

    mode_map =
      put_in(mode_map, [:cmds_to_execute], cmds)
      |> put_in([:step], %{})
      |> put_in([:step, :device_last_cmds], device_last_cmds)
      |> put_in([:step, :started_at], utc_now())
      |> put_in([:active_step], start_with)
      |> put_in([:started_at], utc_now())
      |> put_in([:cycles], 0)
      |> put_in([:elapsed], 0)

    state =
      change_reef_mode(state, reef_mode)
      |> put_in([:reef_mode], reef_mode)
      |> put_in([reef_mode], mode_map)

    case reef_mode do
      :keep_fresh ->
        state
        |> update_reef_mode_cycles()
        |> start_next_cmd_in_step(start_with)

      reef_mode ->
        IO.puts("reef_mode_start/2 unimplemented mode: #{inspect(reef_mode)}")
        state
    end
  end

  defp start_next_cmd_in_step(%{reef_mode: mode} = state, step) do
    import Helen.Time.Helper, only: [utc_now: 0]

    # example:  state -> keep_fresh -> aerate
    cmd_list = get_in(state, [mode, :steps, step])
    active_step = get_in(state, [mode, :active_step])
    steps_to_execute = get_in(state, [mode, :steps_to_execute])

    # NOTE:  each clause returns the state, even if unchanged
    case get_in(state, [mode, :cmds_to_execute]) |> hd() do
      {:repeat, true} ->
        # populate the cmds to execute and call ourself again
        state
        |> update_reef_mode_cycles()
        |> put_in([mode, :cmds_to_execute], cmd_list)
        |> put_in([mode, :step, :started_at], utc_now())
        |> start_next_cmd_in_step(active_step)

      x when x == [] and steps_to_execute == [] ->
        # we've reached the end of this reef mode
        state
        |> reef_mode_complete()

      ##
      ## TODO include handling of multiple steps
      ##

      # this is an actual command to start
      {cmd, cmd_opts} when is_list(cmd_opts) when cmd in [:on, :off] ->
        dev = get_in(state, [mode, :step_devices, active_step])

        apply_cmd(state, dev, cmd, cmd_opts)

        # remove this cmd from the list.  the :at_finish of the command
        # started will move us forward in the list of cmds to execute
        update_in(state, [mode, :cmds_to_execute], fn x -> tl(x) end)
        |> put_in([mode, :step, :cmd], cmd)

      # this is a reference to another step cmd
      # execute the referenced step/cmd
      {step_ref, cmd} when is_atom(cmd) ->
        # steps to execute and call ourself again
        dev = get_in(state, [mode, :step_devices, step_ref])
        cmd_opts = get_in(state, [mode, :sub_steps, step_ref, cmd])
        apply_cmd(state, dev, cmd, cmd_opts)

        state = update_in(state, [mode, :cmds_to_execute], fn x -> tl(x) end)
        # if there is a leader for this reef_mode then call ourselves again
        # since we aren't relying on the :at_finish from this referenced cmd
        # to move us forward
        if get_in(state, [mode, :leader]),
          do: start_next_cmd_in_step(state, active_step),
          else: state
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

  defp will_finish_by_ms(steps) do
    import Helen.Time.Helper, only: [to_ms: 1]

    # unfold each step in the  steps list matching on the key :run_for.
    # convert each value to ms and reduce with a start value of 0.
    for {_step, details} <- steps,
        {k, run_for} when k == :run_for <- details,
        reduce: 0 do
      total_ms -> total_ms + to_ms(run_for)
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
      :salt_mix,
      :prep_for_change,
      :transfer_h2o,
      :finalize_change
    ]

    for m <- modes, reduce: state do
      state -> state |> put_in([m], %{status: :ready})
    end
    |> put_in([:reef_mode], :ready)
  end

  defp update_reef_mode_cycles(%{reef_mode: mode} = state) do
    update_in(state, [mode, :step, :cycles], fn
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

  # defp noreply_and_merge(s, map), do: {:noreply, Map.merge(s, map)}

  defp reply(s, val) when is_map(s), do: {:reply, val, s, loop_timeout(s)}
  defp reply(val, s), do: {:reply, val, s, loop_timeout(s)}
end
