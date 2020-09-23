defmodule Helen.Worker.Logic do
  @moduledoc """
  Logic for Roost server
  """

  @callback active_mode :: atom()
  @callback active_step :: atom()
  @callback all_stop :: term()
  @callback available_modes :: map()
  @callback change_mode(atom()) :: map()
  @callback faults(term() | list()) :: term()
  @callback faults? :: boolean()
  @callback last_timeout :: term()
  @callback mode(atom(), list()) :: term()
  @callback ready? :: boolean()
  @callback restart(list()) :: term()
  @callback runtime_opts :: map()
  @callback server(atom()) :: atom()
  @callback status :: map()
  @callback standby? :: boolean()
  @callback timeout_hook(map()) :: map()

  defmacro __using__(use_opts) do
    # credo:disable-for-next-line
    quote location: :keep, bind_quoted: [use_opts: use_opts] do
      @behaviour Helen.Worker.Logic

      alias Helen.Worker.{Logic, State}
      alias Helen.Worker.State.Common

      def active_mode, do: call({:inquiry, :active_mode})
      def active_step, do: call({:inquiry, :active_step})

      @doc """
      Bring all Workers activities to a stop.

      Returns :ok
      """
      @doc since: "0.0.27"
      def all_stop, do: change_mode(:all_stop)

      @doc """
      Return a list of available Worker modes.

      Returns a list.
      """
      @doc since: "0.0.27"
      def available_modes, do: call({:inquiry, :available_modes})

      @doc false
      def call(msg) do
        if server_down?() do
          {:failed, :server_down}
        else
          GenServer.call(__MODULE__, msg)
        end
      end

      @doc since: "0.0.27"
      def cancel_delayed_cmd, do: call({:cancel_delayed_cmd})

      def change_mode(mode), do: call({:mode, mode, []})

      def execute_action(action), do: action

      def faults(what), do: call({:inquiry, {:faults, what}})
      def faults?, do: call({:inquiry, :faults?})

      @doc false
      @impl true
      def handle_call({call, _args} = msg, _from, state)
          when call in [:inquiry, :server_mode, :state],
          do: Logic.handle_call(msg, state)

      @doc false
      @impl true
      def handle_call({:mode, mode, _api_opts}, _from, state) do
        state
        |> Logic.change_mode(mode)
        |> Logic.check_fault_and_reply()
      end

      @doc false
      @impl true
      def handle_call(msg, _from, state),
        do: state |> Logic.msg_puts(msg) |> Logic.reply({:unmatched_msg, msg})

      # call messages for :logic are quietly ignored if the msg token
      # does not match the current token
      @impl true
      def handle_cast({:logic, msg}, state),
        do: Logic.handle_logic_msg(msg, state) |> Logic.noreply()

      @doc false
      @impl true
      def handle_continue(:bootstrap, state) do
        Logic.bootstrap(state)
        |> Logic.noreply()
      end

      # info messages for :logic are quietly ignored if the msg token
      # does not match the current token
      @impl true
      def handle_info({:logic, msg}, state),
        do: Logic.handle_logic_msg(msg, state) |> Logic.noreply()

      @doc false
      @impl true
      def handle_info(:timeout, state) do
        state
        |> Common.update_last_timeout()
        |> timeout_hook()
      end

      @doc """
      Is the worker holding on a mode?
      """
      @doc since: "0.0.27"
      def holding?, do: call({:inquiry, :holding?})

      @doc """
      Return the DateTime of the last Worker timeout
      """
      @doc since: "0.0.27"
      def last_timeout, do: call({:inquiry, :last_timeout})

      @doc """
      Set the Worker to a specific mode.
      """
      @doc since: "0.0.27"
      def mode(mode, opts \\ []), do: call({:mode, mode, opts})

      @doc """
      Is the server ready?

      Returns true if server is ready, false if server is in standby mode.
      """
      @doc since: "0.0.27"
      def ready?, do: call({:inquiry, :ready?})

      @doc """
      Restarts the server via the Supervisor

      ## Examples

          iex> Roost.Server.restart([])
          :ok

      """
      @doc since: "0.0.27"
      def restart(opts \\ []), do: Logic.restart(__MODULE__, opts)

      @doc """
      Return the worker runtime options.
      """
      @doc since: "0.0.27"
      def runtime_opts, do: call({:inquiry, :runtime_opts})

      @doc """
      Set the Worker to ready or standbyy.

      ## Modes
      When set to `:ready` (normal mode) the Worker is ready to start a mode.

      If set to `:standby` the Worker:
        1. Stops all mode activities (aka full stop)
        2. Denies all change mode requests.

      Returns {:ok, new_mode}

      """
      @doc since: "0.0.27"
      def server(atom) when atom in [:ready, :standby],
        do: call({:server_mode, atom})

      def server_down?, do: GenServer.whereis(__MODULE__) |> is_nil()

      def status, do: call({:inquiry, :status})

      def standby?, do: call({:inquiry, :standby?})

      @doc """
      Retrieve the number of GenServer timeouts that have occurred.
      """
      @doc since: "0.0.27"
      def timeouts, do: call({:inquiry, :timeouts})

      def timeout_hook(state) do
        Logic.noreply(state)
      end

      @doc false
      @impl true
      def terminate(_reason, state), do: state

      defoverridable Helen.Worker.Logic
    end
  end

  ##
  ## END OF USING
  ##

  ##
  ## START OF MODULE
  ##

  require Logger

  import Helen.Worker.State.Common
  import Helen.Worker.State

  def available_modes(%{opts: opts} = _state) do
    get_in(opts, [:modes])
    |> Map.keys()
    |> Enum.sort()
  end

  def bootstrap(state) do
    state
    |> change_token()
    |> cache_worker_modules()
  end

  def cache_worker_modules(%{opts: %{workers: workers}} = state) do
    alias Helen.Workers

    put_in(state, [:workers], Workers.build_module_cache(workers))
  end

  def change_mode(state, mode) do
    if ready?(state) do
      init(state, mode)
      # flag that actions should be executed
      |> execute_actions(true)
      |> start()
    else
      init_fault_put(state, %{server: :standby})
    end
  end

  def check_fault_and_reply(state) do
    if faults?(state) do
      {:reply, {:fault, faults_map(state)}, state, loop_timeout(state)}
    else
      {:reply, {:ok, active_mode(state)}, state, loop_timeout(state)}
    end
  end

  def confirm_mode_exists(state, mode) do
    known_mode? = get_in(state, [:opts, :modes, mode]) || false

    if known_mode? do
      state |> init_fault_clear()
    else
      # otherwise, note the fault
      state |> init_fault_put({:unknown_mode, mode})
    end
  end

  def execute(state) do
    alias Helen.Workers

    state = Workers.execute(state)

    # IO.puts("execute cmd_rc: #{inspect(cmd_rc(state), pretty: true)}")

    case cmd_rc(state) do
      # if this action is processed via a message and a message is expected
      # upon completion then we do not advance to the next action.  the next
      # action is advanced upon receipt and processing of the command complete
      # message.
      %{wait: true} ->
        state

      # a fault occurred while processing the action, store in the state for
      # handling downstream
      %{fault: fault} ->
        action_fault_put(state, fault)

      # no match above indicates the command was processed and there should be
      # no delay prior to the next action
      _cmd_rc ->
        # since the action was executed it is no longer pending
        pending_action_drop(state) |> next_action()
    end
  end

  def execute_actions_if_needed(state) do
    if execute_actions?(state), do: execute(state), else: state
  end

  def finished?(state, mode) do
    case finished_get(state, [mode, :status]) do
      :finished -> true
      _other_status -> false
    end
  end

  def finish_mode(state) do
    import Helen.Time.Helper, only: [utc_now: 0]

    state
    |> update_elapsed()
    |> live_put(:status, :finished)
    |> live_put(:finished_at, utc_now())
    |> move_live_to_finished()
    |> change_token()
  end

  def finish_mode_if_needed(state) do
    case active_mode(state) do
      :none -> state
      _active_mode -> finish_mode(state)
    end
  end

  def handle_call(msg, state) do
    case msg do
      {:inquiry, what} -> handle_inquiry(what, state)
      {:server_mode, mode} -> handle_server_mode(mode, state)
      {:state, _} -> state |> update_elapsed() |> reply(state)
    end
  end

  def handle_inquiry({:inquiry, {:faults, what}}, state),
    do: faults_get(state, what)

  # credo:disable-for-next-line
  def handle_inquiry(x, state) do
    case x do
      :active_mode -> active_mode(state) || :none
      :active_step -> active_step(state) || :none
      :available_modes -> available_modes(state)
      :faults? -> faults?(state)
      :holding? -> holding?(state)
      :last_timeout -> last_timeout(state)
      :live_opts -> opts(state, :live)
      :ready? -> ready?(state)
      :runtime_opts -> opts(state, :runtime)
      :status -> status(state)
      :standby? -> not ready?(state)
      :timeouts -> timeouts(state)
    end
    |> reply(state)
  end

  def handle_logic_msg(%{token: msg_token} = msg, %{token: token} = state)
      when msg_token == token do
    # IO.puts("++++++++++++++++\n")
    # IO.puts(inspect(Map.drop(msg, [:worker_cache]), pretty: true))
    # IO.puts("\n----------------")

    case msg do
      %{via_msg: true, via_msg_at: :at_start} ->
        state

      %{via_msg: true, via_msg_at: :at_finish} ->
        pending_action_drop(state) |> next_action()

      %{via_msg: true} ->
        pending_action_drop(state) |> next_action()

      msg ->
        Logger.info("""
        handle_logic_msg/2
        unmatched msg: #{inspect(Map.drop(msg, [:worker_cache]), pretty: true)}
        """)

        next_action(state)
    end
  end

  def handle_logic_msg(%{token: msg_token} = action, %{token: token} = state)
      when msg_token != token do
    Logger.debug("""
    handle_logic_msg/2
    token mismatch:
    #{inspect(Map.drop(action, [:worker_cache]), pretty: true)}
    """)

    state
  end

  def handle_server_mode(mode, state) do
    case {server_mode(state), mode} do
      # quietly ignore changes to the same mode
      {current, requested} when current == requested ->
        state |> reply({:ok, mode})

      # when switching to :standby ensure the switch is off
      {_current, requested} when requested in [:ready, :standby] ->
        state
        |> change_token()
        |> server_mode(requested)
        |> standby_reason_set(:api)
        |> reply({:ok, mode})
    end
  end

  def holding?(state), do: status_holding?(state)

  def hold_mode(state) do
    state
    |> update_elapsed()
    |> status_put(:holding)
  end

  def init(%{logic: %{faults: %{init: _}}} = state, _mode), do: state

  def init(state, mode) do
    state
    |> build_logic_map()
    |> cache_worker_modules()
    # initialize the :stage map with a copy of the opts that will be used
    # when this mode goes live
    |> copy_opts_to_stage()
    # set the active_mode
    |> stage_put_active_mode(mode)
    |> stage_initialize_steps()
    |> note_delay_if_requested()
  end

  def init_server(mod, args, opts, base_state \\ %{})
      when is_atom(mod) and is_list(args) and is_map(opts) and
             is_map(base_state) do
    state =
      Map.merge(base_state, %{
        module: mod,
        opts: opts,
        timeouts: %{last: :never, count: 0},
        token: nil,
        token_at: nil
      })

    # initial server mode order of precedence:
    #  1. args passed to Worker server
    #  2. defined in configuratin base section
    #  3. defaults to ready
    server_mode = args[:server_mode] || opts(state, :server_mode) || :ready

    state = server_mode(state, server_mode)

    # should the server start?
    if server_mode(state) == :standby do
      :ignore
    else
      {:ok, state, {:continue, :bootstrap}}
    end
  end

  def next_action(state) do
    alias Helen.Workers

    state = update_elapsed(state)
    workers = cached_workers(state)

    # if worker_name(state) == "roost",
    #   do:
    #     Logger.info("""
    #     roost next_action/1 entry status:
    #     status: #{inspect(status(state), pretty: true)}
    #     """)

    case actions_to_execute_get(state) do
      [] ->
        step_repeat_or_next(state)

      [action | _rest] ->
        actions_to_execute_update(state, fn x -> tl(x) end)
        |> pending_action_put(
          Workers.make_action(:logic, workers, action, state)
        )
        |> execute_actions_if_needed()
    end
  end

  def next_mode(state) do
    case live_next_mode(state) do
      :none ->
        finish_mode(state)

      :hold ->
        hold_mode(state)

      # there's a next mode defined
      next_mode ->
        finish_mode(state) |> change_mode(next_mode)
    end
  end

  def noreply(s), do: {:noreply, s, loop_timeout(s)}

  def purge_finished_if_needed(state) do
    if is_atom(stage_get_base_opt(state, :first_mode)) do
      finished_reset(state)
    else
      state
    end
  end

  def repeat_step(state) do
    state
    |> actions_to_execute_put(step_actions_get(state, active_step(state)))
    |> next_action()
  end

  def reply(%{token: _} = s, val),
    do: {:reply, val, update_elapsed(s), loop_timeout(s)}

  def reply(val, %{token: _} = s),
    do: {:reply, val, update_elapsed(s), loop_timeout(s)}

  def restart(mod, opts) do
    # the Supervisor is the base of the module name with Supervisor appended
    [sup_base | _tail] = Module.split(mod)

    sup_mod = Module.concat([sup_base, "Supervisor"])

    if GenServer.whereis(mod) do
      Supervisor.terminate_child(sup_mod, mod)
    end

    Supervisor.delete_child(sup_mod, mod)
    Supervisor.start_child(sup_mod, {mod, opts})
  end

  ##
  ## ENTRY POINT FOR STARTING A REEF MODE
  ##  ** only called once per mode change
  ##
  def start(%{logic: %{faults: %{init: _}}} = state), do: state

  # when :delay has a value we send ourself a :timer message
  # when that timer expires the delay value is removed
  def start(%{stage: %{delay: ms}} = state) do
    import Process, only: [send_after: 3]
    import Helen.Time.Helper, only: [utc_now: 0]

    state
    |> stage_put([:issued_at], utc_now())
    |> stage_put(
      [:delayed_start_timer],
      send_after(self(), {:timer, :delayed_cmd}, ms)
    )
  end

  def start(state) do
    state
    |> finish_mode_if_needed()
    |> purge_finished_if_needed()
    |> move_stage_to_live()
    |> status_put(:running)
    |> track_put(:started_at)
    |> calculate_steps_durations()
    |> detect_sequence_repeats()
    |> calculate_will_finish_by()
    |> track_put(:sequence, stage_get_mode_opts(state, :sequence))
    |> track_copy(:sequence, :steps_to_execute)
    |> start_mode_next_step()
  end

  def start_mode_next_step(state) do
    case steps_to_execute(state) do
      [] ->
        # reached the end of steps
        next_mode(state)

      [:repeat] ->
        track_copy(state, :sequence, :steps_to_execute)
        |> start_mode_next_step()

      [next_step | _] ->
        state
        |> track_put(:active_step, next_step)
        |> steps_to_execute_update(fn x -> tl(x) end)
        |> actions_to_execute_put(step_actions_get(state, next_step))
        |> track_step_started()
        |> next_action()
    end
  end

  def step_repeat_or_next(state) do
    import Helen.Time.Helper, only: [elapsed?: 2]

    run_for = step_run_for(state)

    elapsed = track_step_elapsed_get(state)
    # required = track_calculated_step_duration_get(state, active_step(state))

    # step does not have a run for defined or the required time to repeat
    # this step would exceeded the defined run_for
    if is_nil(run_for) or elapsed?(run_for, [elapsed]) do
      start_mode_next_step(state)

      # there is enough time to repeat the step
    else
      repeat_step(state)
    end
  end

  defdelegate status(state), to: Helen.Worker.Status

  def msg_puts(state, msg) do
    Logger.info("""
     msg_puts #{inspect(msg)}

    """)

    state
  end
end
