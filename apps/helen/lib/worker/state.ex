defmodule Helen.Worker.State do
  @moduledoc false

  import List, only: [flatten: 1]

  def action_fault_put(state, val),
    do: put_in(state, [:logic, :faults, :action], val)

  def actions_to_execute_get(state), do: track_get(state, [:actions_to_execute])

  def actions_to_execute_put(state, actions),
    do: track_put(state, [:actions_to_execute], actions)

  def actions_to_execute_update(state, func) when is_function(func, 1),
    do: track_update(state, [:actions_to_execute], func)

  def active_mode(state), do: live_get(state, :active_mode) || :none
  def active_step(state), do: track_get(state, :active_step) || :none

  def build_logic_map(state) do
    import Map, only: [put_new: 3]

    put_new(state, :logic, %{})
    |> update_in([:logic], fn logic_map ->
      for x <- [:faults, :finished, :live, :stage], reduce: logic_map do
        logic_map -> put_new(logic_map, x, %{})
      end
    end)
  end

  def cached_workers(state), do: get_in(state, [:workers])

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

  def cmd_definition(state, what),
    do: live_get(state, [:opts, :cmd_definitions, what])

  def cmd_rc(state), do: track_get(state, [:cmd_rc])

  def cmd_rc_put(state, val) do
    track_update(state, [:cmd_rc], fn
      nil -> %{}
      x -> x
    end)
    |> track_put([:cmd_rc], val)
  end

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

  def detect_sequence_repeats(state),
    do:
      live_put(
        state,
        :repeat_until_stopped?,
        Enum.member?(live_get_mode_sequence(state), :repeat)
      )

  def execute_actions?(state), do: live_get(state, :execute_actions) || false
  # flag that we want actions to be executed.  used in production.  not used
  # during testing to avoid inifinite loops with repeating steps
  def execute_actions(state, flag), do: stage_put(state, :execute_actions, flag)

  def finished_get(state, path),
    do: get_in(state, flatten([:logic, :finished, path]))

  def finished_mode?(state, mode), do: finished_get(state, mode) || false

  def finished_mode_put(state, mode, mode_map)
      when is_atom(mode) and is_map(mode_map),
      do: put_in(state, [:logic, :finished, mode], mode_map)

  def init_fault_put(state, val),
    do: state |> build_logic_map() |> put_in([:logic, :faults, :init], val)

  def init_fault_clear(state),
    do:
      state
      |> build_logic_map()
      |> update_in([:logic, :faults], fn x -> Map.drop(x, [:init]) end)

  def lasts_put(state, what, val),
    do: put_in(state, flatten([:lasts, what]), val)

  def live_get(state, path),
    do: get_in(state, flatten([:logic, :live, path]))

  def live_get_mode_opt(state, path),
    do:
      live_get(
        state,
        flatten([:opts, :modes, live_get(state, :active_mode), path])
      )

  def live_get_mode_sequence(state), do: live_get_mode_opt(state, :sequence)

  def live_next_mode(state), do: live_get_mode_opt(state, :next_mode) || :none

  def live_get_step(state, step_name),
    do: live_get_steps(state) |> get_in([step_name])

  def live_get_steps(state), do: live_get(state, [:steps])

  def live_opts_get(state, what \\ []),
    do: live_get(state, flatten([:opts, what]))

  def live_put(state, path, val),
    do: put_in(state, [:logic, :live, [path]] |> flatten(), val)

  # def live_put_status(state, status), do: state |> live_put([:status], status)

  def live_update(state, path, func) when is_function(func, 1),
    do: state |> update_in(flatten([:logic, :live, path]), func)

  def mode_repeat_until_stopped?(state),
    do: live_get(state, :repeat_until_stopped?)

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

  def opts_get(state, what \\ []), do: get_in(state, flatten([:opts, what]))
  def opts_mode_names(state), do: opts_get(state, :modes) |> Map.keys()

  def pending_action(state), do: track_get(state, :pending_action) || :none

  def pending_action_put(state, val) do
    IO.puts(
      "subsystem: #{worker_name(state)} pending_action: #{
        inspect(val, pretty: true)
      }"
    )

    track_put(state, :pending_action, val)
  end

  def pending_action_drop(state),
    do: track_update(state, [], fn x -> Map.drop(x, [:pending_action]) end)

  def stage_get(state, path),
    do: get_in(state, flatten([:logic, :stage, path]))

  def stage_get_opts(state, path \\ []),
    do: state |> stage_get(flatten([:opts, path]))

  def stage_get_mode_opts(state, path \\ []) do
    stage_get_opts(
      state,
      flatten([:modes, stage_get(state, :active_mode), path])
    )
  end

  def stage_initialize_steps(state),
    do: state |> stage_put(:steps, stage_get_mode_opts(state, :steps))

  def stage_put(state, path, val),
    do: state |> put_in(flatten([:logic, :stage, path]), val)

  def stage_put_active_mode(state, mode),
    do: state |> stage_put(:active_mode, mode)

  def state_put(state, what, val), do: put_in(state, flatten([what]), val)

  def status_get(state), do: live_get(state, :status) || :none

  def status_put(state, status) do
    state |> live_put(:status, status)
  end

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

  def track_update(state, what \\ [], func) when is_function(func),
    do: state |> update_in(flatten([:logic, :live, :track, [what]]), func)

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

  def worker_name(state), do: opts_get(state, [:base, :worker_name])
end
