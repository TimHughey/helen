defmodule Helen.Worker.State do
  @moduledoc false

  require Logger
  import List, only: [flatten: 1]

  def action_fault_put(state, val),
    do: put_in(state, [:logic, :faults, :action], val)

  def actions_to_execute_get(state), do: track_get(state, [:actions_to_execute])

  def actions_to_execute_put(state, actions),
    do: track_put(state, [:actions_to_execute], actions)

  def actions_to_execute_update(state, func) when is_function(func, 1),
    do: track_update(state, [:actions_to_execute], func)

  def active_mode(state, mode \\ nil) do
    if is_nil(mode) do
      live_get(state, :active_mode) || :none
    else
      live_put(state, :active_mode, mode)
    end
  end

  def active_step(state), do: track_get(state, :active_step) || :none

  def build_logic_map(state) do
    import Map, only: [put_new: 3]

    put_new(state, :logic, %{})
    |> update_in([:logic], fn logic_map ->
      for x <- [:faults, :finished, :live], reduce: logic_map do
        logic_map -> put_new(logic_map, x, %{})
      end
    end)
  end

  def cached_workers(state), do: get_in(state, [:workers])

  def calculate_step_duration(%{for: run_for}) do
    import Helen.Time.Helper, only: [to_duration: 1]
    to_duration(run_for)
  end

  def calculate_step_duration(%{actions: actions}) do
    import Helen.Time.Helper, only: [add_list: 1, zero: 0]

    for action <- actions, reduce: zero() do
      duration ->
        case action do
          %{wait: false} -> duration
          %{for: run_for} -> add_list([duration, run_for])
          _anything -> duration
        end
    end
  end

  def calculate_steps_durations(state) do
    for x <- mode_sequence(state),
        {step_name, details} when x == step_name <- mode_steps(state),
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
    do: get_in(state, [:opts, :commands, what])

  def cmd_rc(state), do: track_get(state, [:cmd_rc])

  def cmd_rc_put(state, val) do
    track_update(state, [:cmd_rc], fn
      nil -> %{}
      x -> x
    end)
    |> track_put([:cmd_rc], val)
  end

  def detect_sequence_repeats(state),
    do:
      live_put(
        state,
        :repeat_until_stopped?,
        Enum.member?(mode_sequence(state), :repeat)
      )

  def execute_actions?(state), do: live_get(state, :execute_actions) || false
  # flag that we want actions to be executed.  used in production.  not used
  # during testing to avoid inifinite loops with repeating steps
  def execute_actions(state, flag), do: live_put(state, :execute_actions, flag)

  def finished_get(state, path),
    do: get_in(state, flatten([:logic, :finished, path]))

  def finished_mode?(state, mode), do: finished_get(state, mode) || false

  def finished_mode_put(state, mode, mode_map)
      when is_atom(mode) and is_map(mode_map),
      do: put_in(state, [:logic, :finished, mode], mode_map)

  def finished_reset(state), do: put_in(state, [:logic, :finished], %{})

  def init_fault_put(state, val),
    do: state |> build_logic_map() |> put_in([:logic, :faults, :init], val)

  def init_fault_clear(state),
    do:
      state
      |> build_logic_map()
      |> update_in([:logic, :faults], fn x -> Map.drop(x, [:init]) end)

  def live_init(state) do
    import Helen.Time.Helper, only: [utc_now: 0]

    state
    |> live_put([], %{
      active_mode: nil,
      active_step: nil,
      steps: %{},
      track: %{},
      temp: %{},
      will_finish_in_ms: 0,
      will_finish_by: nil
    })
  end

  def lasts_put(state, what, val),
    do: put_in(state, flatten([:lasts, what]), val)

  def live_get(state, path),
    do: get_in(state, flatten([:logic, :live, path]))

  def live_next_mode(state), do: mode_opt(state, :next_mode) || :none

  def live_get_step(state, step_name),
    do: mode_steps(state) |> get_in([step_name])

  def mode_steps(state) do
    mode_opt(state, [:steps])
  end

  def live_put(state, path, val),
    do: put_in(state, flatten([:logic, :live, [path]]), val)

  def live_update(state, path, func) when is_function(func, 1),
    do: state |> update_in(flatten([:logic, :live, path]), func)

  def mode_opt(state, path \\ []) do
    active_mode = live_get(state, :active_mode)
    get_in(state, flatten([:opts, :modes, active_mode, :details, path]))
  end

  def mode_sequence(state), do: mode_opt(state, :sequence)

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

  def note_delay_if_requested(%{opts: opts} = state) do
    import Helen.Time.Helper, only: [to_ms: 1, valid_ms?: 1]

    case opts[:start_delay] do
      # just fine, no delay requested
      delay when is_nil(delay) ->
        state

      # delay requested, validate it then store if valid
      delay ->
        if valid_ms?(delay) do
          state
          # store the delay for pattern matching later
          |> live_put([:delay], to_ms(delay))
        else
          state |> init_fault_put({:invalid_delay, delay})
        end
    end
  end

  def pending_action(state), do: track_get(state, :pending_action) || :none

  def pending_action_put(state, val) do
    track_put(state, :pending_action, val)
  end

  def pending_action_drop(state),
    do: track_update(state, [], fn x -> Map.drop(x, [:pending_action]) end)

  def pending_action_meta(state) do
    action = pending_action(state)

    if action === :none,
      do: %{},
      else: get_in(action, [:meta])
  end

  def pending_action_meta_put(state, meta_map) do
    action = pending_action(state) |> put_in([:meta], meta_map)
    pending_action_put(state, action)
  end

  def initialize_steps(state),
    do: state |> live_put(:steps, mode_steps(state))

  def state_put(state, what, val), do: put_in(state, flatten([what]), val)

  def status_get(state), do: live_get(state, :status) || :none

  def status_holding?(state), do: status_get(state) == :holding

  def status_put(state, status) do
    state |> live_put(:status, status)
  end

  def step_actions_get(state, step_name),
    do: live_get(state, [:steps, step_name, :actions])

  def step_elapsed(state), do: track_step_get(state, :elapsed)

  def step_started_at(state), do: track_step_get(state, :started_at)

  def step_run_for(state) do
    import Helen.Time.Helper, only: [to_duration: 1]

    case live_get(state, [:steps, active_step(state), :for]) do
      x when is_nil(x) -> nil
      x when is_binary(x) -> to_duration(x)
      _no_match -> nil
    end
  end

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

  def track_step_get(_state, _what), do: nil

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
end
