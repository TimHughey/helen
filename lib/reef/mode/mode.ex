defmodule Reef.Mode do
  alias Reef.MixTank.{Air, Pump, Rodi}
  alias Reef.DisplayTank.Ato

  def change_token(state) do
    import Helen.Time.Helper, only: [utc_now: 0]

    state
    |> update_in([:token], fn _x -> make_ref() end)
    |> update_in([:token_at], fn _x -> utc_now() end)
  end

  ##
  ## ENTRY POINT FOR STARTING A REEF MODE
  ##  ** only called once per reef mode change
  ##
  def start_mode(state, reef_mode) do
    import Helen.Time.Helper, only: [utc_now: 0]

    # local function to build the device last cmds map for each device
    device_last_cmds =
      for {_k, v} <- get_in(state, [reef_mode, :step_devices]) || [],
          into: %{} do
        map = %{
          off: %{at_finish: nil, at_start: nil},
          on: %{at_finish: nil, at_start: nil}
        }

        {config_device_to_mod(v), map}
      end

    steps = get_in(state, [reef_mode, :steps])

    change_reef_mode(state, reef_mode)
    |> calculate_will_finish_by_if_needed()
    # mode -> :device_last_cmds is 'global' for the mode and not specific
    # to a single step or command
    |> put_in([reef_mode, :steps_to_execute], Keyword.keys(steps))
    |> put_in([reef_mode, :started_at], utc_now())
    |> put_in([reef_mode, :device_last_cmds], device_last_cmds)
    |> put_in([reef_mode, :step], %{})
    |> put_in([reef_mode, :cycles], %{})
    |> start_mode_next_step()
  end

  def start_next_cmd_in_step(%{reef_mode: mode} = state) do
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

      cmds_to_execute == [] ->
        # we've reached the end of this step, start the next one
        state
        |> start_mode_next_step()

      is_binary(run_for) ->
        started_at = get_in(state, [mode, :step, :started_at]) || utc_now()

        # to prevent exceeding the configured run_for include the duration of the
        # step about to start in the elapsed?
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

      true ->
        state |> start_next_cmd_and_pop()
    end
  end

  def step_device_to_mod(dev) do
    case dev do
      :air -> Air
      :pump -> Pump
      :rodi -> Rodi
      :ato -> Ato
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

  defp calculate_will_finish_by_if_needed(%{reef_mode: reef_mode} = state) do
    import Helen.Time.Helper, only: [to_ms: 1, utc_shift: 1]

    # grab the list of steps to avoid redundant traversals
    steps = get_in(state, [reef_mode, :steps])

    # will_finish_by can not be calculated if the reef mode
    # contains the cmd repeat: true
    has_repeat? =
      for {_name, cmds} <- steps, {:repeat, true} <- cmds, reduce: false do
        _acc -> true
      end

    if has_repeat? == true do
      state
    else
      # unfold each step in the steps list matching on the key :run_for.
      # convert each value to ms and reduce with a start value of 0.
      will_finish_by =
        for {_step, details} <- get_in(state, [reef_mode, :steps]),
            {k, run_for} when k == :run_for <- details,
            reduce: 0 do
          total_ms -> total_ms + to_ms(run_for)
        end
        |> utc_shift()

      state |> put_in([reef_mode, :will_finish_by], will_finish_by)
    end
  end

  defp change_reef_mode(%{reef_mode: old_reef_mode} = state, new_reef_mode) do
    update_running_mode_status = fn
      # x, :keep_fresh ->
      #   import Helen.Time.Helper, only: [utc_now: 0]
      #
      #   put_in(x, [:keep_fresh, :status], :completed)
      #   |> put_in([:keep_fresh, :finished_at], utc_now())

      x, _anything ->
        x
    end

    update_running_mode_status.(state, old_reef_mode)
    |> put_in([:reef_mode], new_reef_mode)
    |> change_token()
  end

  defp config_device_to_mod(atom) do
    case atom do
      :air -> Air
      :pump -> Pump
      :rodi -> Rodi
      :ato -> Ato
    end
  end

  defp ensure_sub_steps_off(%{reef_mode: reef_mode} = state) do
    sub_steps = get_in(state, [reef_mode, :sub_steps]) || []

    for {step, _cmds} <- sub_steps do
      dev = get_in(state, [reef_mode, :step_devices, step])
      apply_cmd(state, dev, :off, at_cmd_finish: :off)
    end

    state
  end

  defp finish_mode(%{reef_mode: mode} = state) do
    import Helen.Time.Helper, only: [elapsed: 2, utc_now: 0]

    # record the mode execution metrics
    started_at = get_in(state, [mode, :started_at])
    now = utc_now()

    state
    |> ensure_sub_steps_off()
    |> put_in([mode, :status], :completed)
    |> put_in([mode, :finished_at], now)
    |> put_in([mode, :elapsed], elapsed(started_at, now))
    |> put_in([:reef_mode], :ready)
    |> change_token()
  end

  defp start_mode_next_step(%{reef_mode: reef_mode} = state) do
    import Helen.Time.Helper, only: [utc_now: 0]

    # the next step is always the head of :steps_to_execute
    steps_to_execute = get_in(state, [reef_mode, :steps_to_execute])
    # NOTE:  each clause returns the state, even if unchanged
    cond do
      steps_to_execute == [] ->
        # we've reached the end of this mode!
        state
        |> finish_mode()

      true ->
        next_step = steps_to_execute |> hd()

        cmds = get_in(state, [reef_mode, :steps, next_step])

        state
        # remove the step we're starting
        |> update_in([reef_mode, :steps_to_execute], fn x -> tl(x) end)
        |> put_in([reef_mode, :active_step], next_step)
        # the reef_mode step key contains the control map for the step executing
        |> put_in([reef_mode, :step, :started_at], utc_now())
        |> put_in([reef_mode, :step, :elapsed], 0)
        |> put_in([reef_mode, :step, :run_for], nil)
        |> put_in([reef_mode, :step, :repeat?], nil)
        |> put_in([reef_mode, :step, :cmds_to_execute], cmds)
        |> update_step_cycles()
        |> start_next_cmd_in_step()
    end
  end

  defp start_next_cmd_and_pop(%{reef_mode: mode} = state) do
    next_cmd = get_in(state, [mode, :step, :cmds_to_execute]) |> hd()

    put_in(state, [mode, :step, :next_cmd], next_cmd)
    |> update_in([mode, :step, :cmds_to_execute], fn x -> tl(x) end)
    |> start_next_cmd()
  end

  defp start_next_cmd(%{reef_mode: mode} = state) do
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

      {:msg, _} = msg ->
        GenServer.cast(__MODULE__, msg)
        # if this is the last cmd in the last step (e.g. finally) then the
        # call to start_mode_start_next/1 will wrap up this reef mode
        state |> start_mode_next_step()

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

  defp update_step_cycles(%{reef_mode: mode} = state) do
    active_step = get_in(state, [mode, :active_step])

    update_in(state, [mode, :cycles, active_step], fn
      nil -> 1
      x -> x + 1
    end)
  end
end
