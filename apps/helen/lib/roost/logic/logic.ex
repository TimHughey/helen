defmodule Roost.Logic do
  @moduledoc """
  Logic for Roost server
  """

  def all_stop(%{worker_mode: :ready} = state) do
    # if worker mode is :ready then nothing is running
    # change the token just in case
    state
    |> change_token()
  end

  def all_stop(state) do
    # there's an active worker mode, stop all it's devices, flag the mode
    # as finished and change the token

    state
    # |> finish_mode()
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
      state |> clear_init_fault()
    else
      # otherwise, note the fault
      state |> put_init_fault({:unknown_mode, mode})
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
  ##  ** only called once per reef mode change
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

  def start_mode(%{stage: %{active_mode: _next_mode}} = state) do
    state
    # |> finish_mode_if_needed()
    # swap the pending reef mode map into the live state
    |> move_stage_to_live()
    |> mode_status_put(:started)
    |> mode_track_put(:started_at)
    |> calculate_will_finish_by()
    |> mode_track_put(:steps_to_execute, stage_get_mode_opts(state, :sequence))
    |> start_mode_next_step()
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

  def start_mode_next_step(%{worker_mode: worker_mode} = state) do
    import Helen.Time.Helper, only: [utc_now: 0]

    # the next step is always the head of :steps_to_execute
    steps_to_execute = get_in(state, [worker_mode, :steps_to_execute])
    # NOTE:  each clause returns the state, even if unchanged
    if steps_to_execute == [] do
      # we've reached the end of this mode!
      state
      # |> finish_mode()
    else
      next_step = steps_to_execute |> hd()

      cmds = get_in(state, [worker_mode, :steps, next_step])

      state
      # remove the step we're starting
      |> update_in([worker_mode, :steps_to_execute], fn x -> tl(x) end)
      |> put_in([worker_mode, :active_step], next_step)
      # the worker_mode step key contains the control map for the step executing
      |> put_in([worker_mode, :step, :started_at], utc_now())
      |> put_in([worker_mode, :step, :elapsed], 0)
      |> put_in([worker_mode, :step, :cmds_to_execute], cmds)
      |> start_next_cmd_in_step()
    end
  end

  def start_mode_next_step(state), do: state

  def start_next_cmd_in_step(%{worker_mode: mode} = state) do
    import Helen.Time.Helper, only: [elapsed?: 2, subtract_list: 1, utc_now: 0]

    # active_step = get_in(state, [mode, :active_step])
    cmds_to_execute = get_in(state, [mode, :step, :cmds_to_execute])

    # NOTE:  each clause returns the state, even if unchanged
    if cmds_to_execute == [] do
      # we've reached the end of this step, start the next one
      state
      |> start_mode_next_step()
    else
      state |> start_next_cmd_and_pop()
    end
  end

  def calculate_steps_duration(state) do
    for x <- live_get_mode_sequence(state),
        {step_name, details} when x == step_name <- live_get_steps(state),
        reduce: state do
      state ->
        case details do
          # steps that have a run duration are accumulated
          %{run_for: run_for} ->
            state |> live_accumulate_steps_duration(run_for)

          # steps without a run duration accumulate the actions
          %{actions: actions} ->
            state |> calculate_actions_duration(actions)

          _no_run_for ->
            state
        end
    end
  end

  def calculate_actions_duration(state, actions) do
    for action <- actions, reduce: state do
      state ->
        case action do
          %{for: run_for, wait: true} ->
            state |> live_accumulate_actions_duration(run_for)

          _other_cmds ->
            state
        end
    end
  end

  def calculate_will_finish_by(state) do
    state
    |> live_clear_durations_accumulators()
    |> calculate_steps_duration()
    |> live_detect_sequence_repeats()
    |> live_put_will_finish_by()
  end

  def finish_mode(state) do
    import Helen.Time.Helper, only: [elapsed: 2, utc_now: 0]

    # record the mode execution metrics
    started_at = live_get(state, :started_at)
    now = utc_now()

    state
    |> live_put(:status, :completed)
    |> live_put(:finished_at, now)
    |> live_put(:elapsed, elapsed(started_at, now))
    |> move_live_to_finished()
    |> change_token()
  end

  def finish_mode_if_needed(state) do
    case state do
      %{live: %{active_mode: _mode}} -> finish_mode(state)
      _live -> state
    end
  end

  def move_live_to_finished(%{live: %{active_mode: mode} = live} = state) do
    state
    # remove :active_mode to avoid cruf
    |> live_update_in(fn x -> Map.drop(x, [:active_mode]) end)
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
          state |> put_init_fault({:invalid_delay, delay})
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

  def start_next_cmd_and_pop(%{worker_mode: mode} = state) do
    cmds_to_execute = get_in(state, [mode, :step, :cmds_to_execute]) || []

    cond do
      get_in(state, [mode, :step, :hold_mode]) == true ->
        state

      # no more commands in this step, start the next one
      cmds_to_execute == [] ->
        state |> start_mode_next_step()

      # there are more commands, continue to execute them
      is_list(cmds_to_execute) ->
        next_cmd = hd(cmds_to_execute)

        put_in(state, [mode, :step, :next_cmd], next_cmd)
        |> update_in([mode, :step, :cmds_to_execute], fn x -> tl(x) end)
        |> start_next_cmd()
    end
  end

  def start_next_cmd(%{worker_mode: mode} = state) do
    # active_step = get_in(state, [mode, :active_step])
    this_cmd = get_in(state, [mode, :step, :next_cmd])

    case this_cmd do
      # hold_mode: true cmd signal the step is complete but
      # the mode should run indefinitely
      {:hold_mode, true} ->
        state
        |> put_in([mode, :step, :hold_mode], true)

      # via_msgs are processed indirectly via by handle_info/2
      {:via_msg, true} ->
        # simply skip
        state

      {:send_msg, msg_details} ->
        state
        |> send_cmd_msg(msg_details)

      # cmd 'keywords' above didn't match so this must be:
      #  1. simple on/off list: {:ok | :off, [:dev_atom, | _]}
      #  2. a dev and actions:  {:dev_atom, [cmd: details]}
      {cmd_or_dev, x} when is_atom(cmd_or_dev) and is_list(x) ->
        state
        |> apply_actions({cmd_or_dev, x})
    end
    |> start_next_cmd_and_pop()
  end

  def stop_all_devices(%{opts: opts} = state) do
    devs = get_in(opts, [:devices]) |> Keyword.keys()

    for dev <- devs, reduce: state do
      state -> state |> apply_action_to_dev(dev, :off, [])
    end
  end

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

  def live_put(state, path, val) do
    put_in(state, [:live, [path]] |> List.flatten(), val)
  end

  def live_put_status(state, status) do
    state |> live_put([:status], status)
  end

  def live_put_will_finish_by(
        %{live: %{temp: %{duration: %{repeat: true}}}} = state
      ) do
    state
    |> live_put(:will_finish_in_ms, nil)
    |> live_put(:will_finish_by, nil)
    |> live_put(:repeat_until_stopped?, true)
  end

  def live_put_will_finish_by(
        %{
          live: %{
            temp: %{
              duration: %{
                actions: actions_duration,
                steps: steps_duration,
                repeat: false
              }
            }
          }
        } = state
      ) do
    import Helen.Time.Helper, only: [add_list: 1, to_ms: 1, shift_future: 2]

    # will finish by is defined as the max duration of either the steps or actions
    ms = add_list([actions_duration, steps_duration]) |> to_ms()
    dt = shift_future(mode_track_get(state, :started_at), ms)

    state
    |> live_put(:will_finish_in_ms, ms)
    |> live_put(:will_finish_by, dt)
    |> live_put(:repeat_until_stopped?, false)
  end

  def live_update_in(state, func), do: state |> update_in([:live], func)

  # def live_add_duration_to_will_finish(state, duration) do
  #   import Helen.Time.Helper, only: [to_ms: 1, shift_future: 2]
  #
  #   state
  #   |> update_in([:live, :will_finish_in_ms], fn x -> x + to_ms(duration) end)
  #   |> update_in([:live, :will_finish_by], fn x -> shift_future(x, duration) end)
  # end

  def live_accumulate_actions_duration(state, duration) do
    import Helen.Time.Helper, only: [add_list: 1]

    state
    |> update_in([:live, :temp, :duration, :actions], fn x ->
      add_list([x, [duration]] |> List.flatten())
    end)
  end

  def live_accumulate_steps_duration(state, duration) do
    import Helen.Time.Helper, only: [add_list: 1]

    state
    |> update_in([:live, :temp, :duration, :steps], fn x ->
      add_list([x, [duration]] |> List.flatten())
    end)
  end

  def live_clear_durations_accumulators(state) do
    import Helen.Time.Helper, only: [zero: 0]

    state
    |> update_in([:live, :temp], fn x -> Map.put_new(x, :duration, %{}) end)
    |> put_in([:live, :temp, :duration], %{
      steps: zero(),
      actions: zero(),
      repeat: false
    })
  end

  def live_detect_sequence_repeats(state) do
    state
    |> put_in(
      [:live, :temp, :duration, :repeat],
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
    full_path = [:opts, path] |> List.flatten()
    state |> stage_get(full_path)
  end

  def stage_get_mode_opts(state, path \\ []) do
    mode = stage_get(state, [:active_mode])
    full_path = [:modes, mode, path] |> List.flatten()

    stage_get_opts(state, full_path)
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
      active_mode: %{},
      active_step: %{},
      opts: opts,
      steps: %{},
      track: %{},
      temp: %{},
      will_finish_in_ms: 0,
      will_finish_by: utc_now()
    })
  end

  def put_init_fault(state, val) do
    state |> put_in([:faults, :init], val)
  end

  def clear_init_fault(state) do
    state |> update_in([:faults], fn x -> Map.drop(x, [:init]) end)
  end

  def mode_repeat_until_stopped?(state),
    do: live_get(state, :repeat_until_stopped?)

  def mode_status_put(state, status) do
    state |> live_put([:status], status)
  end

  def mode_track_get(state, what) when is_atom(what) do
    state |> live_get([:track, what])
  end

  def mode_track_put(state, what, val \\ nil) do
    import Helen.Time.Helper, only: [utc_now: 0]

    case what do
      :started_at ->
        state |> live_put([:track, :started_at], utc_now())

      _anything_else ->
        state |> live_put([:track, [what]], val)
    end
  end
end
