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
    |> finish_mode()
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

  def init_precheck(state, mode) do
    state
    |> Map.drop([:init_fault])
    # we use the :stage key to build up the next mode to avoid conflicts
    # if an mode is already running
    |> stage_put([:mode], mode)
    |> stage_put([mode], %{})
    |> confirm_mode_exists(mode)
  end

  def init_mode(%{init_fault: _} = state), do: state

  def init_mode(%{stage: %{mode: mode}} = state) do
    state
    |> stage_put([mode, :steps], stage_get_opts(state, [:steps]))
    |> note_delay_if_requested()
  end

  ##
  ## ENTRY POINT FOR STARTING A REEF MODE
  ##  ** only called once per reef mode change
  ##
  def start_mode(%{init_fault: _} = state), do: state

  # when :delay has a value we send ourself a :timer message
  # when that timer expires the delay value is removed
  def start_mode(%{stage: %{delay: ms}} = state) do
    import Process, only: [send_after: 3]
    import Helen.Time.Helper, only: [utc_now: 0]

    state
    |> stage_put([:issued_at], utc_now())
    |> stage_put(
      [:timer],
      send_after(self(), {:timer, :delayed_cmd}, ms)
    )
  end

  def start_mode(%{stage: %{mode: next_mode} = next_mode_map} = state) do
    state
    # swap the pending reef mode map into the live state
    |> live_put([next_mode], next_mode_map)
    |> change_worker_mode()
    # :pending is no longer required
    |> Map.drop([:pending])
    |> calculate_will_finish_by_if_needed()
    |> put_in([next_mode, :status], :running)
    |> put_in([next_mode, :step], %{})
    |> start_mode_next_step()
  end

  # support calls where the action is tuple by wrapping it in a list
  defp apply_actions(state, action) when is_tuple(action),
    do: apply_actions(state, [action])

  defp apply_actions(%{opts: opts} = state, actions) do
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

  defp apply_action_to_dev(state, dev, func, func_opt) do
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

  defp start_mode_next_step(%{worker_mode: worker_mode} = state) do
    import Helen.Time.Helper, only: [utc_now: 0]

    # the next step is always the head of :steps_to_execute
    steps_to_execute = get_in(state, [worker_mode, :steps_to_execute])
    # NOTE:  each clause returns the state, even if unchanged
    if steps_to_execute == [] do
      # we've reached the end of this mode!
      state
      |> finish_mode()
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

  defp calculate_will_finish_by_if_needed(%{worker_mode: worker_mode} = state) do
    import Helen.Time.Helper, only: [to_ms: 1, utc_shift: 1]

    # grab the list of steps to save get_in's
    steps = get_in(state, [:modes, worker_mode, :steps]) || []

    cond do
      has_key?(steps, :repeat) ->
        state

      has_key?(steps, :run_for) ->
        # unfold each step in the steps list matching on the key :run_for.
        # convert each value to ms and reduce with a start value of 0.
        will_finish_by =
          for {_step, details} <- steps,
              {k, run_for} when k == :run_for <- details,
              reduce: 0 do
            total_ms -> total_ms + to_ms(run_for)
          end
          |> utc_shift()

        state |> put_in([worker_mode, :will_finish_by], will_finish_by)

      true ->
        will_finish_by =
          for {_name, cmds} <- steps,
              {cmd, cmd_details} when cmd in [:on, :off] <- cmds,
              {:for, cmd_for} <- cmd_details,
              reduce: 0 do
            total_ms -> total_ms + to_ms(cmd_for)
          end
          |> utc_shift()

        state |> put_in([worker_mode, :will_finish_by], will_finish_by)
    end
  end

  defp change_worker_mode(
         %{worker_mode: worker_mode, pending: %{worker_mode: next_mode}} = state
       ) do
    import Helen.Time.Helper, only: [utc_now: 0]

    # grab the next reef mode steps to use in the pipeline below
    next_steps = get_in(state, [:pending, next_mode, :steps]) || []

    # start by "finishing" the running mode (if there is one)
    for {m, %{status: :running}} when m == worker_mode <- state,
        reduce: state do
      state ->
        state
        |> put_in([m, :status], :finished)
        |> put_in([m, :finished_at], utc_now())
    end
    # now setup the next reef mode for execution
    |> put_in([:worker_mode], next_mode)
    |> put_in([next_mode, :steps_to_execute], Keyword.keys(next_steps))
    |> put_in([next_mode, :started_at], utc_now())
    |> change_token()
  end

  defp confirm_mode_exists(%{opts: opts} = state, mode) do
    known_mode? = get_in(state, [:opts, :modes, mode]) || false

    if known_mode? do
      # make a copy of the opts for use while running the mode
      # to allow the server opts to be changed without impacting the
      # running mode
      state |> put_in([:stage, :opts], opts)
    else
      state |> put_in([:init_fault], {:unknown_mode, mode})
    end
  end

  defp finish_mode(%{worker_mode: mode} = state) do
    import Helen.Time.Helper, only: [elapsed: 2, utc_now: 0]

    # record the mode execution metrics
    started_at = get_in(state, [mode, :started_at])
    now = utc_now()

    state
    |> put_in([mode, :status], :completed)
    |> put_in([mode, :finished_at], now)
    |> put_in([mode, :elapsed], elapsed(started_at, now))
    |> put_in([:worker_mode], :ready)
    |> change_token()
  end

  defp has_key?(steps, key) do
    for {_name, cmds} <- steps,
        {k, _value} when k == key <- cmds,
        reduce: false do
      _acc -> true
    end
  end

  defp note_delay_if_requested(%{init_fault: _} = state), do: state

  defp note_delay_if_requested(%{stage: %{mode: mode}} = state) do
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
          # take out of opts to avoid cruf
          |> update_in([:stage, mode, :opts], fn x ->
            Keyword.drop(x, [:start_delay])
          end)
        else
          state |> put_in([:init_fault], :invalid_delay)
        end
    end
  end

  defp send_cmd_msg(%{worker_mode: mode, token: msg_token} = state, msg_details) do
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

  defp start_next_cmd_and_pop(%{worker_mode: mode} = state) do
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

  defp start_next_cmd(%{worker_mode: mode} = state) do
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

  defp stop_all_devices(%{opts: opts} = state) do
    devs = get_in(opts, [:devices]) |> Keyword.keys()

    for dev <- devs, reduce: state do
      state -> state |> apply_action_to_dev(dev, :off, [])
    end
  end

  defp live_get(state, path) do
    full_path = [:live, path] |> List.flatten()

    get_in(state, full_path)
  end

  defp live_put(state, path, val) do
    full_path = [:live, path] |> List.flatten()

    put_in(state, full_path, val)
  end

  defp stage_get(state, path) do
    full_path = [:stage, path] |> List.flatten()

    get_in(state, full_path)
  end

  def stage_get_opts(%{stage: %{mode: mode}} = state, path \\ []) do
    full_path = [:opts, :modes, mode, path] |> List.flatten()
    stage_get(state, full_path)
  end

  defp stage_put(state, path, val) do
    full_path = [:stage, path] |> List.flatten()

    put_in(state, full_path, val)
  end
end
