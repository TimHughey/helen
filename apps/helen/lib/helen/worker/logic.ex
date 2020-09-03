defmodule Helen.Worker.Logic do
  @moduledoc """
  Logic for Roost server
  """

  @callback active_mode(map()) :: atom()
  @callback active_step(map()) :: atom()
  @callback available_modes :: map()
  @callback change_token(map()) :: map()
  @callback change_mode(map(), atom()) :: map()
  @callback check_fault_and_reply(map()) :: {atom(), tuple()}
  @callback faults(map(), atom() | list()) :: term()
  @callback faults?(map()) :: boolean()
  @callback init(map(), atom()) :: map()
  @callback noreply(map()) :: any()
  @callback reply(any(), map()) :: any()
  @callback status(map()) :: atom()
  @callback token(map()) :: reference()

  defmacro __using__(use_opts) do
    quote location: :keep, bind_quoted: [use_opts: use_opts] do
      @behaviour Helen.Worker.Logic

      alias Helen.Worker.{Logic, State}

      def active_mode(state), do: State.live_get(state, :active_mode) || :none
      def active_step(state), do: State.track_get(state, :active_step) || :none

      @doc """
      Bring all Workers activities to a stop.

      Returns :ok
      """
      @doc since: "0.0.27"
      def all_stop, do: call({:all_stop})

      @doc """
      Return a list of available Worker modes.

      Returns a list.
      """
      @doc since: "0.0.27"
      def available_modes, do: call({:inquiry, :available_modes})

      def call(msg) do
        if server_down?() do
          {:failed, :server_down}
        else
          GenServer.call(__MODULE__, msg)
        end
      end

      @doc since: "0.0.27"
      def cancel_delayed_cmd, do: call({:cancel_delayed_cmd})

      def change_token(state), do: State.change_token(state)

      def change_mode(state, mode) do
        Logic.init(state, mode)
        |> Logic.start()
        |> Logic.execute()
      end

      def check_fault_and_reply(state) do
        import Helen.Worker.State, only: [loop_timeout: 1]

        if faults?(state) do
          {:reply, {:fault, faults(state, [])}, state, loop_timeout(state)}
        else
          {:reply, {:ok, active_mode(state)}, state, loop_timeout(state)}
        end
      end

      def faults(state, what), do: Logic.faults(state, what)
      def faults?(state), do: Logic.faults?(state)

      def init(state, mode), do: Logic.init(state, mode)

      @doc false
      @impl true
      def handle_call({:inquiry, what}, _from, state),
        do: Logic.handle_inquiry(state, what) |> reply(state)

      @doc false
      @impl true
      def handle_call(:state, _from, state) do
        import Helen.Worker.State, only: [update_elapsed: 1]

        state |> update_elapsed() |> reply(state)
      end

      # call messages for :logic are quietly ignored if the msg token
      # does not match the current token
      @impl true
      def handle_cast({:logic, %{token: msg_token}}, %{token: token} = state)
          when msg_token != token,
          do: noreply(state)

      @doc false
      @impl true
      def handle_continue(:bootstrap, state) do
        state
        |> change_token()
        |> noreply()
      end

      # info messages for :logic are quietly ignored if the msg token
      # does not match the current token
      @impl true
      def handle_info({:logic, %{token: msg_token}}, %{token: token} = state)
          when msg_token != token,
          do: noreply(state)

      @impl true
      def handle_info({:logic, logic_msg}, state),
        do: Logic.handle_logic_msg(logic_msg, state)

      @impl true
      def handle_info(
            {:logic, {:via_msg, _step}, msg_token} = msg,
            %{token: token} = state
          )
          when msg_token == token do
        Logic.handle_via_msg(state, msg) |> noreply()
      end

      # handle step via messages
      @impl true
      def handle_info(
            {:msg, {:via_msg, _step}, msg_token} = _msg,
            %{token: token} = state
          )
          when msg_token != token do
        noreply(state)
      end

      @doc false
      @impl true
      def handle_info(:timeout, state) do
        state
        |> State.update_last_timeout()
        |> timeout_hook()
      end

      @doc """
      Return the DateTime of the last Worker timeout
      """
      @doc since: "0.0.27"
      def last_timeout, do: call({:inquiry, :last_timeout})

      @doc """
      Set the Worker to a specific mode.
      """
      @doc since: "0.0.27"
      def mode(mode, opts), do: call({:mode, mode, opts})

      def noreply(s), do: Logic.noreply(s)

      @doc """
      Is the server ready?

      Returns true if server is ready, false if server is in standby mode.
      """
      @doc since: "0.0.27"
      def ready?, do: call({:inquiry, :ready?})

      def reply(s, val) when is_map(s), do: Logic.reply(s, val)
      def reply(val, s) when is_map(s), do: Logic.reply(val, s)

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

      def server_down? do
        GenServer.whereis(__MODULE__) |> is_nil()
      end

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
      def server_mode(atom) when atom in [:ready, :standby] do
        call({:server_mode, atom})
      end

      def status(state), do: Logic.status(state)

      def standby?, do: call({:inquiry, :standby?})

      @doc """
      Retrieve the number of GenServer timeouts that have occurred.
      """
      @doc since: "0.0.27"
      def timeouts, do: call({:inquiry, :timeouts})

      def timeout_hook(state) do
        noreply(state)
      end

      @doc false
      @impl true
      def terminate(_reason, state), do: state

      def token(state), do: State.token(state)

      defoverridable Helen.Worker.Logic
    end
  end

  ##
  ## END OF USING
  ##

  ##
  ## START OF MODULE
  ##

  import Helen.Worker.State

  def all_stop(state) do
    state
    |> finish_mode_if_needed()
    |> change_token()
  end

  def available_modes(%{opts: opts} = _state) do
    get_in(opts, [:modes])
    |> Map.keys()
    |> Enum.sort()
  end

  def cache_worker_modules(%{opts: %{workers: workers}} = state) do
    alias Helen.Workers

    put_in(state, [:workers], Workers.build_module_cache(workers))
  end

  def cached_workers(state), do: get_in(state, [:workers])

  def confirm_mode_exists(state, mode) do
    known_mode? = get_in(state, [:opts, :modes, mode]) || false

    if known_mode? do
      state |> init_fault_clear()
    else
      # otherwise, note the fault
      state |> init_fault_put({:unknown_mode, mode})
    end
  end

  def faults(state, what), do: faults_get(state, what)

  def faults?(state) do
    case get_in(state, [:logic, :faults]) do
      %{init: %{}} -> true
      _x -> false
    end
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

  def handle_inquiry(state, what) do
    case what do
      :available_modes ->
        available_modes(state)

      :last_timeout ->
        last_timeout(state)

      :live_opts ->
        opts(state, :live)

      :ready? ->
        ready?(state)

      :runtime_opts ->
        opts(state, :runtime)

      :standby? ->
        not ready?(state)

      :timeouts ->
        timeouts(state)
        # {:x_state, keys} when is_list(keys) -> x_state(state, keys)
    end
  end

  def handle_logic_msg(_logic_msg, state), do: next_action(state)

  # TODO
  def handle_via_msg(
        %{logic: %{live: %{active_mode: _active_mode}}} = state,
        {:logic, {:via_msg, _step}, _msg_token}
      ) do
    # this is a via message sent while processing the worker mode steps
    # so we must look up the step included in the message
    # step_to_execute = get_in(state, [mode, :steps, step])
    #
    # # eliminate the actual via msg flag
    # actions = Keyword.drop(step_to_execute, [:via_msg])

    state
  end

  # not a message we have logic for, just pass through state
  def handle_via_msg(state, _no_match), do: state

  def holding?(state), do: status_get(state) == :holding

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
    |> live_put_status(:initialized)
  end

  def next_action(state) do
    import Helen.Workers, only: [make_action: 4]

    state = update_elapsed(state)
    workers = cached_workers(state)

    case actions_to_execute_get(state) do
      [] ->
        step_repeat_or_next(state)

      [action | rest] ->
        actions_to_execute_update(state, fn _x -> rest end)
        |> pending_action_put(fn ->
          make_action(:logic, workers, action, token(state))
        end)
    end
  end

  def next_mode(state) do
    case live_next_mode(state) do
      :none -> finish_mode(state)
      :hold -> hold_mode(state)
      # there's a next mode defined
      next_mode -> finish_mode(state) |> init(next_mode) |> start()
    end
  end

  def noreply(s), do: {:noreply, s, loop_timeout(s)}

  def repeat_step(state) do
    state
    |> actions_to_execute_put(step_actions_get(state, active_step(state)))
    |> next_action()
  end

  def reply(s, val) when is_map(s),
    do: {:reply, val, update_elapsed(s), loop_timeout(s)}

  def reply(val, s) when is_map(s),
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
    |> move_stage_to_live()
    |> status_put(:started)
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
        |> status_put(:running)
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
    required = track_calculated_step_duration_get(state, active_step(state))

    # step does not have a run for defined or the required time to repeat
    # this step would exceeded the defined run_for
    if is_nil(run_for) or elapsed?(run_for, [elapsed, required]) do
      start_mode_next_step(state)

      # there is enough time to repeat the step
    else
      repeat_step(state)
    end
  end

  def status(state), do: status_get(state)

  def execute(state) do
    alias Helen.Workers

    state = Workers.execute(state)

    case cmd_rc(state) do
      # if this action is processed via a message and a message is expected
      # upon completion then we do not advance to the next action.  the next
      # action is advanced upon receipt and processing of the command complete
      # message.
      %{cmd_rc: %{via_msg: true}} -> state
      # a fault occurred while processing the action, store in the state for
      # handling downstream
      %{cmd_rd: %{fault: fault}} -> action_fault_put(state, fault)
      # no match above indicates the command was processed and there should be
      # no delay prior to the next action
      _nomatch -> next_action(state)
    end
  end
end
