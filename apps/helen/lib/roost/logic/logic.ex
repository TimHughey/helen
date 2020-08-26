defmodule Roost.Logic do
  @moduledoc """
  Logic for Roost server
  """

  def all_stop(state) do
    state
    |> finish_mode_if_needed()
    |> stop_all_devices()
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

  def handle_via_msg(
        %{worker_mode: mode} = state,
        {:msg, {:via_msg, step}, _msg_token}
      ) do
    # this is a via message sent while processing the worker mode steps
    # so we must look up the step included in the message
    step_to_execute = get_in(state, [mode, :steps, step])

    # eliminate the actual via msg flag
    actions = Keyword.drop(step_to_execute, [:via_msg])

    state |> apply_actions(actions)
  end

  # not a message we have logic for, just pass through state
  def handle_via_msg(state, _np_match), do: state

  def init_mode(%{faults: %{init: _}} = state, _mode), do: state

  def init_mode(state, mode) do
    state
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
  def start_mode(%{faults: %{init: _}} = state), do: state

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

  def start_mode_next_step(%{live: %{track: %{steps_to_execute: []}}} = state) do
    state |> finish_mode()
  end

  def start_mode_next_step(
        %{live: %{track: %{steps_to_execute: [:repeat]}}} = state
      ) do
    # steps are repeating, copy the sequence into steps to execute and call ourself
    state |> track_copy(:sequence, :steps_to_execute) |> start_mode_next_step()
  end

  def start_mode_next_step(
        %{live: %{track: %{steps_to_execute: [next_step | _tail]}}} = state
      ) do
    import Helen.Time.Helper, only: [utc_now: 0]

    state
    |> status_put(:running)
    |> track_put(:active_step, next_step)
    |> steps_to_execute_update(fn x -> tl(x) end)
    |> actions_to_execute_put(step_actions_get(state, next_step))
    |> track_step_started()
    |> next_action()
  end

  def action_complete(state) do
    state
    |> track_action_execute_clear()
    |> next_action()
  end

  def next_action(
        %{
          live: %{
            track: %{
              actions_to_execute: []
            }
          }
        } = state
      ) do
    state |> start_mode_next_step()
  end

  def next_action(
        %{
          live: %{
            track: %{
              actions_to_execute: [next_action | _tail]
            }
          }
        } = state
      ) do
    state
    |> actions_to_execute_update(fn x -> tl(x) end)
    |> track_action_execute_put(next_action)
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

  def calculate_will_finish_by(%{live: %{repeat_until_stopped?: true}} = state) do
    state
    |> live_put(:will_finish_in_ms, nil)
    |> live_put(:will_finish_by, nil)
  end

  def calculate_will_finish_by(
        %{
          live: %{
            repeat_until_stopped?: false,
            track: %{
              calculated_durations: step_durations,
              started_at: started_at
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
    import Helen.Time.Helper, only: [elapsed: 2, utc_now: 0]

    # record the mode execution metrics
    started_at = live_get(state, :started_at)
    now = utc_now()

    state
    |> live_put(:status, :finished)
    |> live_put(:finished_at, now)
    |> live_put(:elapsed, elapsed(started_at, now))
    |> move_live_to_finished()
    |> change_token()
  end

  def finish_mode_if_needed(state) do
    case state do
      %{live: %{active_mode: mode}} when is_atom(mode) -> finish_mode(state)
      _live -> state
    end
  end

  def move_live_to_finished(%{live: %{active_mode: mode} = live} = state) do
    state
    # remove :active_mode to avoid cruf
    |> live_update([], fn x -> Map.drop(x, [:active_mode]) end)
    # place a copy of live into finished
    |> finished_put_mode(mode, live)
    # clear live
    |> live_put([], %{})
  end

  def move_stage_to_live(%{stage: stage} = state) do
    state |> put_in([:live], stage) |> put_in([:stage], %{})
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

  # def start_next_cmd(%{worker_mode: mode} = state) do
  #   # active_step = get_in(state, [mode, :active_step])
  #   this_cmd = get_in(state, [mode, :step, :next_cmd])
  #
  #   case this_cmd do
  #     # hold_mode: true cmd signal the step is complete but
  #     # the mode should run indefinitely
  #     {:hold_mode, true} ->
  #       state
  #       |> put_in([mode, :step, :hold_mode], true)
  #
  #     # via_msgs are processed indirectly via by handle_info/2
  #     {:via_msg, true} ->
  #       # simply skip
  #       state
  #
  #     {:send_msg, msg_details} ->
  #       state
  #       |> send_cmd_msg(msg_details)
  #
  #     # cmd 'keywords' above didn't match so this must be:
  #     #  1. simple on/off list: {:ok | :off, [:dev_atom, | _]}
  #     #  2. a dev and actions:  {:dev_atom, [cmd: details]}
  #     {cmd_or_dev, x} when is_atom(cmd_or_dev) and is_list(x) ->
  #       state
  #       |> apply_actions({cmd_or_dev, x})
  #   end
  #   |> start_next_cmd_and_pop()
  # end

  def stop_all_devices(%{opts: opts} = state) do
    devs = get_in(opts, [:devices]) |> Keyword.keys()

    for dev <- devs, reduce: state do
      state -> state |> apply_action_to_dev(dev, :off, [])
    end
  end

  def actions_to_execute_put(state, actions),
    do: track_put(state, [:actions_to_execute], actions)

  def actions_to_execute_update(state, func) when is_function(func, 1),
    do: track_update(state, [:actions_to_execute], func)

  def finished_get(state, path),
    do: get_in(state, [:finished, [path]] |> List.flatten())

  def finished_put_mode(state, mode, mode_map)
      when is_atom(mode) and is_map(mode_map),
      do: put_in(state, [:finished, mode], mode_map)

  def live_get(state, path),
    do: get_in(state, [:live, [path]] |> List.flatten())

  def live_get_mode_opt(%{live: %{active_mode: active_mode}} = state, path),
    do: live_get(state, [:opts, :modes, active_mode, [path]] |> List.flatten())

  def live_get_mode_sequence(state), do: live_get_mode_opt(state, :sequence)

  def live_get_step_for(%{live: %{active_mode: active_mode}} = state, step)
      when is_atom(step) do
    live_get(state, [:opts, :modes, active_mode, [step]] |> List.flatten())
  end

  def live_get_step(state, step_name),
    do: live_get_steps(state) |> get_in([step_name])

  def live_get_steps(state), do: live_get(state, [:steps])

  def live_steps_to_execute(%{live: %{steps_to_execute: x}}), do: x

  def live_put(state, path, val) do
    put_in(state, [:live, [path]] |> List.flatten(), val)
  end

  def live_put_status(state, status) do
    state |> live_put([:status], status)
  end

  def finished?(state, mode) do
    case finished_get(state, [mode, :status]) do
      :finished -> true
      _other_status -> false
    end
  end

  def live_update(state, path, func) when is_function(func, 1),
    do: state |> update_in(List.flatten([:live, path]), func)

  def detect_sequence_repeats(state) do
    live_put(
      state,
      :repeat_until_stopped?,
      Enum.member?(live_get_mode_sequence(state), :repeat)
    )
  end

  def stage_get(state, path) do
    full_path = [:stage, path] |> List.flatten()

    get_in(state, full_path)
  end

  def stage_initialize_steps(state) do
    state |> stage_put(:steps, stage_get_mode_opts(state, :steps))
  end

  def stage_get_opts(state, path \\ []) do
    state |> stage_get(List.flatten([:opts, path]))
  end

  def stage_get_mode_opts(state, path \\ []) do
    stage_get_opts(
      state,
      List.flatten([:modes, stage_get(state, :active_mode), path])
    )
  end

  def stage_put(state, path, val) do
    # we use the :stage key to build up the next mode to avoid conflicts
    # if a mode is already running
    full_path = [:stage, path] |> List.flatten()

    state |> put_in(full_path, val)
  end

  def stage_put_active_mode(state, mode) do
    state |> stage_put(:active_mode, mode)
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

  def init_fault_put(state, val) do
    state |> put_in([:faults, :init], val)
  end

  def init_fault_clear(state) do
    state |> update_in([:faults], fn x -> Map.drop(x, [:init]) end)
  end

  def mode_repeat_until_stopped?(state),
    do: live_get(state, :repeat_until_stopped?)

  def status_put(state, status) do
    state |> live_put([:status], status)
  end

  def step_actions_get(%{live: %{steps: steps}}, step_name) do
    get_in(steps, [step_name, :actions])
  end

  def steps_to_execute_update(state, func) do
    track_update(state, :steps_to_execute, func)
  end

  def track_calculated_step_duration_get(state, step_name) do
    state
    |> track_get([:calculated_durations, step_name])
  end

  def track_calculated_step_duration_put(state, step_name, duration) do
    state
    |> track_update([], fn x -> Map.put_new(x, :calculated_durations, %{}) end)
    |> track_put([:calculated_durations, step_name], duration)
  end

  def track_copy(state, from, to) do
    state |> track_put(to, track_get(state, from))
  end

  def track_get(state, what) do
    state |> live_get([:track, what])
  end

  def track_update(state, what \\ [], func) when is_function(func) do
    state |> update_in(List.flatten([:live, :track, [what]]), func)
  end

  def track_put(state, what, val \\ nil) do
    import Helen.Time.Helper, only: [utc_now: 0]

    case what do
      :started_at ->
        state |> live_put([:track, :started_at], utc_now())

      _anything_else ->
        state |> live_put([:track, [what]], val)
    end
  end

  def action_to_execute?(state) do
    case track_action_execute_get(state) do
      x when is_nil(x) -> false
      _x -> true
    end
  end

  def track_action_execute_clear(state), do: track_put(state, [:execute], nil)

  def track_action_execute_get(state), do: track_get(state, [:execute])

  def track_action_execute_put(
        %{
          live: %{active_mode: active_mode, track: %{active_step: active_step}},
          token: token
        } = state,
        action
      ) do
    execute = %{
      token: token,
      mode: active_mode,
      step: active_step,
      action: action
    }

    state
    |> track_put([:execute], execute)
  end

  def track_step_get(
        %{live: %{track: %{active_step: active_step}}} = state,
        what
      ) do
    state
    |> track_get([:steps, active_step, what])
  end

  def track_step_put(
        %{live: %{track: %{active_step: active_step}}} = state,
        what,
        val
      ) do
    state
    |> update_in([:live, :track], fn x -> Map.put_new(x, :steps, %{}) end)
    |> update_in([:live, :track, :steps], fn x ->
      Map.put_new(x, active_step, %{})
    end)
    |> track_put([:steps, active_step, what], val)
  end

  def track_step_started(state) do
    import Helen.Time.Helper, only: [utc_now: 0, zero: 0]

    state
    |> track_step_put(:started_at, utc_now())
    |> track_step_put(:elapsed, zero())
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
    rc = apply(PulseWidth, func, List.flatten([dev_name, func_opt]))

    state
    |> put_in([:devices, dev, :lasts, :rc], rc)
    |> put_in([:devices, dev, :lasts, :at], utc_now())
    |> put_in([:devices, dev, :lasts, :cmd], {func, func_opt})
  end
end
