defmodule Reef.Mode do
  def available_modes(%{opts: opts} = _state) do
    Keyword.drop(opts, [:__available__, :__version__])
    |> Keyword.keys()
    |> Enum.sort()
  end

  def change_token(state) do
    import Helen.Time.Helper, only: [utc_now: 0]

    state
    |> update_in([:token], fn _x -> make_ref() end)
    |> update_in([:token_at], fn _x -> utc_now() end)
  end

  def init_precheck(state, worker_mode, override_opts) do
    state
    |> Map.drop([:init_fault])
    # we use the :pending key to build up the next reef command to
    # avoid conflicts if a reef command is running
    |> put_in([:pending], %{})
    |> put_in([:pending, :worker_mode], worker_mode)
    |> put_in([:pending, worker_mode], %{})
    |> confirm_worker_mode_exists(worker_mode)
    |> assemble_and_put_final_opts(override_opts)
    |> validate_opts()
    |> validate_durations()
  end

  def init_mode(%{init_fault: _} = state), do: state

  def init_mode(%{pending: %{worker_mode: worker_mode}} = state) do
    cmd_opts = get_in(state, [:pending, worker_mode, :opts])

    state
    |> put_in([:pending, worker_mode, :steps], cmd_opts[:steps])
    |> put_in([:pending, worker_mode, :sub_steps], cmd_opts[:sub_steps])
    |> put_in([:pending, worker_mode, :step_devices], cmd_opts[:step_devices])
    |> build_device_last_cmds_map()
    |> note_delay_if_requested()
  end

  defp note_delay_if_requested(%{init_fault: _} = state), do: state

  defp note_delay_if_requested(%{pending: %{worker_mode: worker_mode}} = state) do
    import Helen.Time.Helper, only: [to_ms: 1, valid_ms?: 1]

    opts = get_in(state, [:pending, worker_mode, :opts])

    case opts[:start_delay] do
      # just fine, no delay requested
      delay when is_nil(delay) ->
        state

      # delay requested, validate it then store if valid
      delay ->
        if valid_ms?(delay) do
          state
          # store the delay for pattern matching later
          |> put_in([:pending, :delay], to_ms(delay))
          # take out of opts to avoid cruf
          |> update_in([:pending, worker_mode, :opts], fn x ->
            Keyword.drop(x, [:start_delay])
          end)
        else
          state |> put_in([:init_fault], :invalid_delay)
        end
    end
  end

  ##
  ## ENTRY POINT FOR STARTING A REEF MODE
  ##  ** only called once per reef mode change
  ##
  def start_mode(%{init_fault: _} = state), do: state

  # when :delay has a value we send ourself a :timer message
  # when that timer expires the delay value is removed
  def start_mode(%{pending: %{delay: ms}} = state) do
    import Process, only: [send_after: 3]
    import Helen.Time.Helper, only: [utc_now: 0]

    state
    |> put_in([:pending, :issued_at], utc_now())
    |> put_in(
      [:pending, :timer],
      send_after(self(), {:timer, :delayed_cmd}, ms)
    )
  end

  def start_mode(%{pending: %{worker_mode: next_mode}} = state) do
    next_mode_map = get_in(state, [:pending, next_mode])

    state
    # swap the pending reef mode map into the live state
    |> put_in([next_mode], next_mode_map)
    |> change_worker_mode()
    # :pending is no longer required
    |> Map.drop([:pending])
    |> calculate_will_finish_by_if_needed()
    |> put_in([next_mode, :status], :running)
    |> put_in([next_mode, :step], %{})
    |> put_in([next_mode, :cycles], %{})
    |> start_mode_next_step()
  end

  defp start_mode_next_step(%{worker_mode: worker_mode} = state) do
    import Helen.Time.Helper, only: [utc_now: 0]

    # the next step is always the head of :steps_to_execute
    steps_to_execute = get_in(state, [worker_mode, :steps_to_execute])
    # NOTE:  each clause returns the state, even if unchanged
    cond do
      steps_to_execute == [] ->
        # we've reached the end of this mode!
        state
        |> finish_mode()

      true ->
        next_step = steps_to_execute |> hd()

        cmds = get_in(state, [worker_mode, :steps, next_step])

        state
        # remove the step we're starting
        |> update_in([worker_mode, :steps_to_execute], fn x -> tl(x) end)
        |> put_in([worker_mode, :active_step], next_step)
        # the worker_mode step key contains the control map for the step executing
        |> put_in([worker_mode, :step, :started_at], utc_now())
        |> put_in([worker_mode, :step, :elapsed], 0)
        |> put_in([worker_mode, :step, :run_for], nil)
        |> put_in([worker_mode, :step, :repeat?], nil)
        |> put_in([worker_mode, :step, :cmds_to_execute], cmds)
        |> update_step_cycles()
        |> start_next_cmd_in_step()
    end
  end

  def start_next_cmd_in_step(%{worker_mode: mode} = state) do
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

      # run_for was specified and we've reached the end of the cmds to
      # execute so repopulate the cmds to execute and drop the run_for key.
      # if the run_for key isn't dropped it will be processed again thereby
      # turning this into repeat: true rather than a time limited execution.
      #
      # call ourself and let the next match determine if this step should
      # continue
      cmds_to_execute == [] and is_binary(run_for) ->
        cmds =
          get_in(state, [mode, :steps, active_step]) |> Keyword.drop([:run_for])

        state
        # note that we're executing another cycle
        |> update_step_cycles()
        |> put_in([mode, :step, :cmds_to_execute], cmds)
        |> start_next_cmd_in_step

      # run ror check
      is_binary(run_for) ->
        started_at = get_in(state, [mode, :step, :started_at]) || utc_now()

        # to prevent exceeding the configured run_for include the duration of the
        # step about to start in the elapsed check
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

      cmds_to_execute == [] ->
        # we've reached the end of this step, start the next one
        state
        |> start_mode_next_step()

      true ->
        state |> start_next_cmd_and_pop()
    end
  end

  def step_device_to_mod(dev) do
    alias Reef.{MixTank, DisplayTank}

    case dev do
      :handoff -> :handoff
      :air -> MixTank.Air
      :pump -> MixTank.Pump
      :rodi -> MixTank.Rodi
      :ato -> DisplayTank.Ato
      :mixtank_temp -> MixTank.Temp
      :display_temp -> DisplayTank.Temp
    end
  end

  defp add_notify_opts_include_token(%{token: t}, opts),
    do: [opts, notify: [:at_start, :at_finish, token: t]] |> List.flatten()

  defp apply_cmd(state, dev, cmd, opts)
       when dev in [:air, :pump, :rodi, :ato] and cmd in [:on, :off] do
    cmd_opts = add_notify_opts_include_token(state, opts)

    apply(step_device_to_mod(dev), cmd, [cmd_opts])
  end

  # skip unmatched commands, devices
  defp apply_cmd(_state, _dev, _cmd, _opts), do: {:no_match}

  defp assemble_and_put_final_opts(%{init_fault: _} = state, _overrides),
    do: state

  defp assemble_and_put_final_opts(
         %{pending: %{worker_mode: worker_mode}, opts: opts} = state,
         overrides
       ) do
    import DeepMerge, only: [deep_merge: 2]

    api_opts = [overrides] |> List.flatten()

    config_opts = get_in(opts, [worker_mode])
    final_opts = deep_merge(config_opts, api_opts)

    state
    |> put_in([:pending, worker_mode, :opts], %{})
    |> put_in([:pending, worker_mode, :opts], final_opts)
  end

  defp build_device_last_cmds_map(
         %{pending: %{worker_mode: worker_mode}} = state
       ) do
    state = put_in(state, [:pending, worker_mode, :device_last_cmds], %{})

    # :none is a special value that signifies no cmd messages are expected so
    # don't create a map entry
    for {_k, v} when v != :none <-
          get_in(state, [:pending, worker_mode, :step_devices]) || [],
        reduce: state do
      state ->
        cmd_map = %{
          off: %{at_finish: nil, at_start: nil},
          on: %{at_finish: nil, at_start: nil}
        }

        mod = step_device_to_mod(v)

        state
        |> put_in([:pending, worker_mode, :device_last_cmds, mod], cmd_map)
    end
  end

  defp confirm_worker_mode_exists(state, worker_mode) do
    known_worker_mode? = get_in(state, [:opts, worker_mode]) || false

    if known_worker_mode? do
      state |> put_in([:pending, :worker_mode], worker_mode)
    else
      state |> put_in([:init_fault], {:unknown_worker_mode, worker_mode})
    end
  end

  def validate_all_durations(%{opts: opts} = _state) do
    validate_duration_r(opts, true)
  end

  defp validate_durations(%{init_fault: _} = state), do: state

  # primary entry point for validating durations
  defp validate_durations(%{pending: %{worker_mode: worker_mode}} = state) do
    opts = get_in(state, [:pending, worker_mode, :opts])

    # validate the opts with an initial accumulator of true so an empty
    # list is considered valid
    if validate_duration_r(opts, true),
      do: state,
      else: state |> put_in([:init_fault], :duration_validation_failed)
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

      # process the head (tuple) and the tail (a list or a tuple)
      {[head | tail], acc} ->
        acc && validate_duration_r(head, acc) &&
          validate_duration_r(tail, acc)

      # keep unfolding
      {{_, v}, acc} when is_list(v) ->
        acc && validate_duration_r(v, acc)

      # we have a tuple to check
      {{k, d}, acc} when k in [:run_for, :for] and is_binary(d) ->
        acc && valid_ms?(d)

      # not a tuple of interest, keep going
      {_no_interest, acc} ->
        acc
    end
  end

  defp validate_opts(%{init_fault: _} = state), do: state
  # TODO implement!!
  defp validate_opts(state), do: state

  # defp initialization_fault?(%{init_fault: _} = _state), do: true
  # defp initialization_fault?(_state), do: false

  defp calculate_will_finish_by_if_needed(%{worker_mode: worker_mode} = state) do
    import Helen.Time.Helper, only: [to_ms: 1, utc_shift: 1]

    # grab the list of steps to save get_in's
    steps = get_in(state, [worker_mode, :steps]) || []

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

  defp ensure_sub_steps_off(%{worker_mode: worker_mode} = state) do
    sub_steps = get_in(state, [worker_mode, :sub_steps]) || []

    for {step, _cmds} <- sub_steps do
      dev = get_in(state, [worker_mode, :step_devices, step])
      apply_cmd(state, dev, :off, at_cmd_finish: :off)
    end

    state
  end

  defp finish_mode(%{worker_mode: mode} = state) do
    import Helen.Time.Helper, only: [elapsed: 2, utc_now: 0]

    # record the mode execution metrics
    started_at = get_in(state, [mode, :started_at])
    now = utc_now()

    state
    |> ensure_sub_steps_off()
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

  defp send_msg(state, {_to, _cmd} = msg) do
    case msg do
      {:handoff, _mode} ->
        GenServer.cast(state[:module], {:msg, msg})

      {to, mode} when to in [:mixtank_temp, :display_temp] ->
        mod = step_device_to_mod(to)
        apply(mod, :mode, [mode])
    end

    state
  end

  defp start_next_cmd_and_pop(%{worker_mode: mode} = state) do
    cmds_to_execute = get_in(state, [mode, :step, :cmds_to_execute]) || []

    case cmds_to_execute do
      # no more commands in this step, start the next one
      [] ->
        state |> start_mode_next_step()

      # there are more commands, continue to execute them
      pending_cmds when is_list(pending_cmds) ->
        next_cmd = hd(pending_cmds)

        put_in(state, [mode, :step, :next_cmd], next_cmd)
        |> update_in([mode, :step, :cmds_to_execute], fn x -> tl(x) end)
        |> start_next_cmd()
    end
  end

  defp start_next_cmd(%{worker_mode: mode} = state) do
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

      {:msg, {_to, _arg} = msg} ->
        state
        |> send_msg(msg)
        # start_next_cmd_and_pop will handle end of list conditions
        |> start_next_cmd_and_pop

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

        # only attempt to process the sub step if we located the
        # device and opts.  if we couldn't then the step doesn't make
        # sense and is quietly skipped
        if is_atom(dev) and is_list(cmd_opts),
          do: apply_cmd(state, dev, cmd, cmd_opts)

        state |> start_next_cmd_in_step()
    end
  end

  defp update_step_cycles(%{worker_mode: mode} = state) do
    active_step = get_in(state, [mode, :active_step])

    update_in(state, [mode, :cycles, active_step], fn
      nil -> 1
      x -> x + 1
    end)
  end
end
