defmodule Helen.Worker.Logic do
  @moduledoc """
  Logic for Roost server
  """

  @callback available_modes_get(map()) :: map()
  @callback change_token(map()) :: map()
  @callback init_mode(map(), atom()) :: map()
  @callback start_mode(map()) :: map()

  @callback noreply(map()) :: any()
  @callback reply(any(), map()) :: any()

  defmacro __using__(use_opts) do
    quote location: :keep, bind_quoted: [use_opts: use_opts] do
      @behaviour Helen.Worker.Logic

      alias Helen.Worker.Logic

      def available_modes_get(state), do: Logic.available_modes(state)
      def change_token(state), do: Logic.change_token(state)
      def init_mode(state, mode), do: Logic.init_mode(state, mode)
      def start_mode(state), do: Logic.start_mode(state)

      # call messages for :logic are quietly ignored if the msg token
      # does not match the current token
      @impl true
      def handle_cast({:logic, %{token: msg_token}}, %{token: token} = state)
          when msg_token != token,
          do: noreply(state)

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

      def token(state), do: Logic.token(state)
    end
  end

  ## END OF USING ##
  ##
  ## START OF MODULE ##

  import List, only: [flatten: 1]

  def active_mode(state), do: live_get(state, :active_mode) || :none
  def active_step(state), do: track_get(state, :active_step) || :none

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

  def build_devices_map(%{opts: opts} = state) do
    for {dev_key, dev_name} when is_binary(dev_name) <- opts[:devices] || [],
        reduce: state do
      state ->
        state
        |> put_in([:devices, dev_key], %{name: dev_name, lasts: %{}})
    end
  end

  def cache_worker_modules(%{opts: %{workers: workers}} = state) do
    alias Helen.Workers

    put_in(state, [:workers], Workers.build_module_cache(workers))
  end

  def cached_workers(state), do: get_in(state, [:workers])

  def change_token(state) do
    import Helen.Time.Helper, only: [utc_now: 0]

    state
    |> update_in([:token], fn _x -> make_ref() end)
    |> update_in([:token_at], fn _x -> utc_now() end)
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

  def faults?(state) do
    case get_in(state, [:logic, :faults]) do
      %{init: %{}} -> true
      _x -> false
    end
  end

  def faults_get(state, what) do
    get_in(state, flatten([:logic, :faults, what]))
  end

  def handle_logic_msg(_logic_msg, state), do: state

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

  def init_mode(%{logic: %{faults: %{init: _}}} = state, _mode), do: state

  def init_mode(state, mode) do
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

  ##
  ## ENTRY POINT FOR STARTING A REEF MODE
  ##  ** only called once per mode change
  ##
  def start_mode(%{logic: %{faults: %{init: _}}} = state), do: state

  # when :delay has a value we send ourself a :timer message
  # when that timer expires the delay value is removed
  def start_mode(%{stage: %{delay: ms}} = state) do
    import Process, only: [send_after: 3]
    import Helen.Time.Helper, only: [utc_now: 0]

    state
    |> stage_put([:issued_at], utc_now())
    |> stage_put(
      [:delayed_start_timer],
      send_after(self(), {:timer, :delayed_cmd}, ms)
    )
  end

  def start_mode(state) do
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

  def repeat_step(state) do
    state
    |> actions_to_execute_put(step_actions_get(state, active_step(state)))
    |> next_action()
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
        |> execute_pending_action()
    end
  end

  def build_logic_map(state) do
    import Map, only: [put_new: 3]

    put_new(state, :logic, %{})
    |> update_in([:logic], fn logic_map ->
      for x <- [:faults, :finished, :live, :stage], reduce: logic_map do
        logic_map -> put_new(logic_map, x, %{})
      end
    end)
  end

  def calculate_step_duration(%{run_for: run_for}), do: run_for

  def calculate_step_duration(%{actions: actions}) do
    import Helen.Time.Helper, only: [add_list: 1, zero: 0]

    for action <- actions, reduce: zero() do
      duration ->
        case action do
          %{for: run_for, wait: true} ->
            add_list([duration, run_for])

          _other_cmds ->
            duration
        end
    end
  end

  def calculate_steps_durations(state) do
    for x <- live_get_mode_sequence(state),
        {step_name, details} when x == step_name <- live_get_steps(state),
        reduce: state do
      state ->
        duration = calculate_step_duration(details)

        track_calculated_step_duration_put(state, step_name, duration)
    end
  end

  def calculate_will_finish_by(
        %{logic: %{live: %{repeat_until_stopped?: true}}} = state
      ) do
    state
    |> live_put(:will_finish_in_ms, nil)
    |> live_put(:will_finish_by, nil)
  end

  def calculate_will_finish_by(
        %{
          logic: %{
            live: %{
              repeat_until_stopped?: false,
              track: %{
                calculated_durations: step_durations,
                started_at: started_at
              }
            }
          }
        } = state
      ) do
    import Helen.Time.Helper, only: [shift_future: 2, to_ms: 1]

    # initialize will_finish_by to started_at then shift into the future
    # each duration
    for {_step_name, duration} <- step_durations,
        reduce: live_put(state, :will_finish_by, started_at) do
      state ->
        state
        |> live_update(:will_finish_in_ms, fn x -> x + to_ms(duration) end)
        |> live_update(:will_finish_by, fn x -> shift_future(x, duration) end)
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

  def hold_mode(state) do
    state
    |> update_elapsed()
    |> status_put(:holding)
  end

  def next_mode(state) do
    case live_next_mode(state) do
      :none -> finish_mode(state)
      :hold -> hold_mode(state)
      # there's a next mode defined
      next_mode -> finish_mode(state) |> init_mode(next_mode) |> start_mode()
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

  def move_live_to_finished(
        %{logic: %{live: %{active_mode: mode} = live}} = state
      ) do
    state
    # remove :active_mode to avoid cruf
    |> live_update([], fn x -> Map.drop(x, [:active_mode]) end)
    # place a copy of live into finished
    |> finished_mode_put(mode, live)
    # clear live
    |> live_put([], %{})
  end

  def move_stage_to_live(%{logic: %{stage: stage}} = state) do
    state |> put_in([:logic, :live], stage) |> put_in([:logic, :stage], %{})
  end

  def note_delay_if_requested(state) do
    import Helen.Time.Helper, only: [to_ms: 1, valid_ms?: 1]

    opts = stage_get_opts(state)

    case opts[:start_delay] do
      # just fine, no delay requested
      delay when is_nil(delay) ->
        state

      # delay requested, validate it then store if valid
      delay ->
        if valid_ms?(delay) do
          state
          # store the delay for pattern matching later
          |> stage_put([:delay], to_ms(delay))
        else
          state |> init_fault_put({:invalid_delay, delay})
        end
    end
  end

  def send_cmd_msg(%{worker_mode: mode, token: msg_token} = state, msg_details) do
    import Helen.Time.Helper, only: [to_ms: 1]

    # trick to ensure :after (if included) is first in the list
    msg_details = Enum.sort(msg_details)

    for {key, val} when key in [:after, :msg] <- msg_details, reduce: state do
      state ->
        case {key, val} do
          {:after, iso_bin} ->
            # temporarily store the send after milliseconds in the state
            state |> put_in([mode, :step, :send_after_ms], to_ms(iso_bin))

          {:msg, msg} ->
            after_ms = get_in(state, [mode, :step, :send_after_ms]) || 0

            Process.send_after(self(), {:msg, msg, msg_token}, after_ms)
            # remove send after milliseconds if it was placed in the state
            state
            |> update_in([mode, :step], fn x ->
              Map.drop(x, [:send_after_ms])
            end)
        end
    end
  end

  def stop_all_devices(%{opts: opts} = state) do
    devs = get_in(opts, [:devices]) |> Keyword.keys()

    for dev <- devs, reduce: state do
      state -> state |> apply_action_to_dev(dev, :off, [])
    end
  end

  def actions_to_execute_get(state), do: track_get(state, [:actions_to_execute])

  def actions_to_execute_put(state, actions),
    do: track_put(state, [:actions_to_execute], actions)

  def actions_to_execute_update(state, func) when is_function(func, 1),
    do: track_update(state, [:actions_to_execute], func)

  def finished_get(state, path),
    do: get_in(state, flatten([:logic, :finished, path]))

  def finished_mode_put(state, mode, mode_map)
      when is_atom(mode) and is_map(mode_map),
      do: put_in(state, [:logic, :finished, mode], mode_map)

  def live_get(state, path),
    do: get_in(state, flatten([:logic, :live, path]))

  def live_get_mode_opt(state, path),
    do: live_get(state, flatten([:opts, :modes, active_mode(state), path]))

  def live_get_mode_sequence(state), do: live_get_mode_opt(state, :sequence)

  def live_next_mode(state), do: live_get_mode_opt(state, :next_mode) || :none

  def live_get_step_for(state, step) when is_atom(step),
    do: live_get(state, flatten([:opts, :modes, active_mode(state), step]))

  def live_get_step(state, step_name),
    do: live_get_steps(state) |> get_in([step_name])

  def live_get_steps(state), do: live_get(state, [:steps])

  def live_put(state, path, val),
    do: put_in(state, [:logic, :live, [path]] |> flatten(), val)

  def live_put_status(state, status), do: state |> live_put([:status], status)

  def finished?(state, mode) do
    case finished_get(state, [mode, :status]) do
      :finished -> true
      _other_status -> false
    end
  end

  def holding?(state), do: status_get(state) == :holding

  def live_update(state, path, func) when is_function(func, 1),
    do: state |> update_in(flatten([:logic, :live, path]), func)

  def detect_sequence_repeats(state),
    do:
      live_put(
        state,
        :repeat_until_stopped?,
        Enum.member?(live_get_mode_sequence(state), :repeat)
      )

  def stage_get(state, path),
    do: get_in(state, flatten([:logic, :stage, path]))

  def stage_initialize_steps(state),
    do: state |> stage_put(:steps, stage_get_mode_opts(state, :steps))

  def stage_get_opts(state, path \\ []),
    do: state |> stage_get(flatten([:opts, path]))

  def stage_get_mode_opts(state, path \\ []) do
    stage_get_opts(
      state,
      flatten([:modes, stage_get(state, :active_mode), path])
    )
  end

  def stage_put(state, path, val),
    do: state |> put_in(flatten([:logic, :stage, path]), val)

  def stage_put_active_mode(state, mode),
    do: state |> stage_put(:active_mode, mode)

  def copy_opts_to_stage(%{opts: opts} = state) do
    import Helen.Time.Helper, only: [utc_now: 0]

    state
    |> stage_put([], %{
      active_mode: nil,
      active_step: nil,
      opts: opts,
      steps: %{},
      track: %{},
      temp: %{},
      will_finish_in_ms: 0,
      will_finish_by: nil
    })
  end

  def init_fault_put(state, val),
    do: state |> build_logic_map() |> put_in([:logic, :faults, :init], val)

  def init_fault_clear(state),
    do:
      state
      |> build_logic_map()
      |> update_in([:logic, :faults], fn x -> Map.drop(x, [:init]) end)

  def mode_repeat_until_stopped?(state),
    do: live_get(state, :repeat_until_stopped?)

  def status_get(state), do: live_get(state, [:status])
  def status_put(state, status), do: state |> live_put([:status], status)

  def step_actions_get(state, step_name),
    do: live_get(state, [:steps, step_name, :actions])

  def step_run_for(state),
    do: live_get(state, [:steps, active_step(state), :for])

  def steps_to_execute(%{logic: %{live: %{track: %{steps_to_execute: x}}}}),
    do: x

  def steps_to_execute_update(state, func),
    do: track_update(state, :steps_to_execute, func)

  def track_calculated_step_duration_get(state, step_name),
    do:
      state
      |> track_get([:calculated_durations, step_name])

  def track_calculated_step_duration_put(state, step_name, duration),
    do:
      state
      |> track_update([], fn x -> Map.put_new(x, :calculated_durations, %{}) end)
      |> track_put([:calculated_durations, step_name], duration)

  def track_copy(state, from, to),
    do: state |> track_put(to, track_get(state, from))

  def track_get(state, what), do: state |> live_get([:track, what])

  def track_update(state, what \\ [], func) when is_function(func),
    do: state |> update_in(flatten([:logic, :live, :track, [what]]), func)

  def track_put(state, what, val \\ nil) do
    import Helen.Time.Helper, only: [utc_now: 0, zero: 0]

    case what do
      :started_at ->
        state
        |> live_put([:track, :started_at], utc_now())
        |> live_put([:track, :elapsed], zero())

      _anything_else ->
        state |> live_put([:track, what], val)
    end
  end

  def track_step_elapsed_get(state), do: track_step_get(state, :elapsed)

  def track_step_get(
        %{logic: %{live: %{track: %{active_step: active_step}}}} = state,
        what
      ) do
    state
    |> track_get([:steps, active_step, what])
  end

  def track_step_put(
        %{logic: %{live: %{track: %{active_step: active_step}}}} = state,
        what,
        val
      ) do
    state
    |> update_in([:logic, :live, :track], fn x ->
      Map.put_new(x, :steps, %{})
    end)
    |> update_in([:logic, :live, :track, :steps], fn x ->
      Map.put_new(x, active_step, %{})
    end)
    |> track_put([:steps, active_step, what], val)
  end

  def track_step_update(state, what, func) when is_function(func, 1),
    do: track_update(state, flatten([:steps, active_step(state), what]), func)

  def track_step_started(state) do
    import Helen.Time.Helper, only: [utc_now: 0, zero: 0]

    state
    |> track_step_put(:started_at, utc_now())
    |> track_step_put(:elapsed, zero())
  end

  def track_step_cycles_increment(state) do
    state
    |> track_step_update(:cycles, fn
      nil -> 1
      x when is_integer(x) -> x + 1
    end)
  end

  def update_elapsed(
        %{logic: %{live: %{track: %{started_at: started_at}}}} = state
      ) do
    import Helen.Time.Helper, only: [elapsed: 2, utc_now: 0]

    now = utc_now()

    state
    |> live_update(:elapsed, fn _x -> elapsed(started_at, now) end)
    |> track_step_update(:elapsed, fn _x ->
      elapsed(track_step_get(state, :started_at), now)
    end)
  end

  # allow update_elapsed/1 calls when there isn't a mode running
  def update_elapsed(state), do: state

  def pending_action_get(state) do
    track_get(state, :pending_action)
  end

  def pending_action_put(state, func) do
    track_put(state, :pending_action, func.())
  end

  def execute_pending_action(state) do
    state
  end

  # support calls where the action is tuple by wrapping it in a list
  def apply_actions(state, action) when is_tuple(action),
    do: apply_actions(state, [action])

  def apply_actions(%{opts: opts} = state, actions) do
    # wrap and flatten the actions parameter to handle either a tuple or
    # list of tuples from the caller
    for {cmd_or_dev, details} <- actions, reduce: state do
      state ->
        case {cmd_or_dev, details} do
          # simple on/off for a list of devices
          {cmd, devs} when cmd in [:on, :off] ->
            for dev when is_atom(dev) <- devs, reduce: state do
              state ->
                state
                # the function to execute is the cmd (:on or :off) and
                # no additional options
                |> apply_action_to_dev(dev, cmd, [])
            end

          {dev, [{func, x}]} when func == :random and is_atom(x) ->
            cmd_map = get_in(opts, [:cmd_definitions, x])

            state
            |> apply_action_to_dev(dev, func, cmd_map)

          # a specific device, function and function opts
          {dev, [{func, func_opt}]} ->
            state
            |> apply_action_to_dev(dev, func, func_opt)
        end
    end
  end

  def apply_action_to_dev(state, dev, func, func_opt) do
    import Helen.Time.Helper, only: [utc_now: 0]

    dev_name = get_in(state, [:devices, dev, :name])

    # here is where the actual device is changed
    # List.flatten/1 is used to ensure a wrapped list of options
    rc = apply(PulseWidth, func, flatten([dev_name, func_opt]))

    state
    |> put_in([:devices, dev, :lasts, :rc], rc)
    |> put_in([:devices, dev, :lasts, :at], utc_now())
    |> put_in([:devices, dev, :lasts, :cmd], {func, func_opt})
  end

  def token(%{token: token}), do: token
end
