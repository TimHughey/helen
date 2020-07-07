defmodule Garden.Lighting.Logic do
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

  def ensure_devices_map(%{opts: opts} = state) do
    for {_job_name, job_details} <- opts[:jobs],
        {:device, dev_name} <- job_details,
        reduce: state do
      state -> state |> put_in([:devices, dev_name], %{})
    end
  end

  def execute_job(state, job_atom, tod) do
    device = get_in(state, [:opts, :jobs, job_atom, :device])
    cmd = get_in(state, [:opts, :jobs, job_atom, :schedule, tod, :cmd])

    case cmd do
      x when is_nil(x) ->
        IO.puts(
          inspect(get_in(state, [:opts, :jobs, job_atom, :schedule, tod]),
            pretty: true
          )
        )

        state

      x when x == :off ->
        state |> put_in([:devices, device, :last_rc], PulseWidth.off(device))

      x when x == :on ->
        state |> put_in([:devices, device, :last_rc], PulseWidth.on(device))

      x when is_atom(x) ->
        cmd_map = get_in(state, [:opts, :cmd_definitions, cmd])

        # as of 2020-07-07 we only support PulseWidth.random/2

        state
        |> put_in(
          [:devices, device, :last_rc],
          PulseWidth.random(device, cmd_map)
        )
    end
  end

  def schedule_jobs_if_needed(%{opts: opts} = state) do
    import Agnus, only: [current?: 0]
    import Helen.Time.Helper, only: [local_now: 1]
    import Timex, only: [day: 1]

    last_scheduled = get_in(state, [:last_scheduled])
    now = local_now(opts[:timezone])
    next_day? = day(now) > day(last_scheduled)

    cond do
      # handles the startup case when Agnus does not yet have info for us
      is_nil(last_scheduled) and current?() -> state |> schedule_jobs()
      # handles the case when it's a new day
      current?() and next_day? -> state |> schedule_jobs()
      # handles when nothing needs scheduling
      true -> state
    end
  end

  defp schedule_jobs(%{opts: opts, token: token} = state) do
    alias Helen.Scheduler
    alias Quantum.Job

    # import Atom, only: [to_string: 1]
    import Helen.Time.Helper, only: [local_now: 1]

    # iterate through the keyword list :jobs from the opts selecting only
    # the key :schedule
    for {job_atom, job_details} <- opts[:jobs],
        {:schedule, tod_list} <- job_details,
        {tod, tod_details} <- tod_list do
      # for this job, iterate through the key/value pairs of time-of-day and
      # duration options to schedule each job

      job_name =
        ["garden", to_string(job_atom), to_string(tod)]
        |> Enum.join("_")
        |> String.to_atom()

      Scheduler.delete_job(job_name)

      Scheduler.new_job()
      |> Job.set_name(job_name)
      |> Job.set_schedule(make_crontab(tod_details))
      |> Job.set_timezone(opts[:timezone])
      |> Job.set_task(fn ->
        Lighting.start_job(job_atom, tod, token)
      end)
      |> Scheduler.add_job()
    end

    state
    |> put_in([:last_scheduled], local_now(opts[:timezone]))
  end

  defp make_crontab(job_details) do
    import Helen.Time.Helper, only: [shift_future: 2, shift_past: 2]
    alias Crontab.CronExpression, as: Cron

    ref = Agnus.sun_info(job_details[:sun_ref])

    backward = job_details[:before]
    forward = job_details[:after]

    %{hour: hour, month: month, minute: minute, second: second, day: day} =
      cond do
        is_binary(backward) -> ref |> shift_past(backward)
        is_binary(forward) -> ref |> shift_future(forward)
        true -> ref
      end

    %Cron{
      extended: true,
      second: [second],
      minute: [minute],
      hour: [hour],
      month: [month],
      day: [day]
    }
  end

  def validate_all_durations(%{opts: opts} = _state) do
    validate_duration_r(opts, true)
  end

  # defp validate_durations(%{init_fault: _} = state), do: state

  # # primary entry point for validating durations
  # defp validate_durations(%{pending: %{worker_mode: worker_mode}} = state) do
  #   opts = get_in(state, [:pending, worker_mode, :opts])
  #
  #   # validate the opts with an initial accumulator of true so an empty
  #   # list is considered valid
  #   if validate_duration_r(opts, true),
  #     do: state,
  #     else: state |> put_in([:init_fault], :duration_validation_failed)
  # end

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
      {{k, d}, acc} when k in [:before, :after, :timeout] and is_binary(d) ->
        acc && valid_ms?(d)

      # not a tuple of interest, keep going
      {_no_interest, acc} ->
        acc
    end
  end

  # defp validate_opts(%{init_fault: _} = state), do: state
  # # TODO implement!!
  # defp validate_opts(state), do: state
end
