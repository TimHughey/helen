defmodule Irrigation.Server do
  @moduledoc """
  Controls the irrigation of Wiss Landing
  """

  use Timex
  use GenServer, restart: :transient, shutdown: 7000
  use Helen.Module.Config

  ##
  ## GenServer Start and Initialization
  ##

  @doc false
  @impl true
  def init(args) do
    import TimeSupport, only: [epoch: 0]

    state = %{
      last_timeout: epoch(),
      timeouts: 0,
      opts: config_opts(args),
      last_scheduled: nil,
      jobs: %{running: %{}, last_rc: %{}},
      faults: %{}
    }

    if valid_opts?(state),
      do: {:ok, state, {:continue, :bootstrap}},
      else: :ignore
  end

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ##
  ## Public API
  ##

  def last_timeout do
    import TimeSupport, only: [epoch: 0, utc_now: 0]

    with last <- state(:last_timeout),
         d when d > 0 <- Timex.diff(last, epoch()) do
      Timex.to_datetime(last, "America/New_York")
    else
      _epoch -> epoch()
    end
  end

  def timeouts, do: state() |> Map.get(:timeouts)

  def start_job(job_name, job_atom, tod_atom, duration_list) do
    GenServer.cast(
      __MODULE__,
      {:start_job, job_name, job_atom, tod_atom, duration_list}
    )
  end

  def state(keys \\ []) do
    keys = [keys] |> List.flatten()
    state = GenServer.call(__MODULE__, :state)

    case keys do
      [] -> state
      [x] -> Map.get(state, x)
      x -> Map.take(state, [x])
    end
  end

  def restart do
    Supervisor.terminate_child(Irrigation.Supervisor, __MODULE__)
    Supervisor.restart_child(Irrigation.Supervisor, __MODULE__)
  end

  ##
  ## GenServer handle_* callbacks
  ##

  @doc false
  @impl true
  def handle_continue(:bootstrap, s) do
    Process.flag(:trap_exit, true)

    Switch.off_names_begin_with(s[:opts][:device_group])

    # NOTE:
    #  schedule_jobs_if_needed/1 handles the possible race condition / delay
    #  related to Agnus acquiring sun info at start up.  if sun info isn't
    #  available yet scheduling is attempted at the next timeout.
    state = schedule_jobs_if_needed(s)

    noreply(state)
  end

  @doc false
  @impl true
  def handle_call(:state, _from, s), do: reply(s, s)

  @doc false
  @impl true
  def handle_cast(
        {:start_job, job_name, job, tod, d},
        %{jobs: jobs, opts: opts} = s
      ) do
    alias Helen.Scheduler

    # power up the +12v for the valves
    state = power_on_if_needed(s)

    pid = spawn_link(fn -> spawned_job(job_name, job, tod, d, opts) end)

    running = Map.put(jobs[:running], pid, job_name)

    state = put_in(state[:jobs][:running], running)

    noreply(state)
  end

  @doc false
  @impl true
  def handle_cast({:job_ending, pid, job_name, last_rc}, %{jobs: jobs} = s) do
    alias Helen.Scheduler

    # the job is done, remove it from the scheduler
    # NOTE:  the next job will be scheduled during a timeout the next day
    Scheduler.delete_job(job_name)

    # remove the job from the running map
    running = Map.drop(jobs[:running], [pid])
    # add the job's last_rc {rc, run_duration}
    last_rc_map = Map.put(jobs[:last_rc], job_name, last_rc)

    state = put_in(s[:jobs][:running], running)
    state = put_in(state[:jobs][:last_rc], last_rc_map)

    state = power_off_if_needed(state)

    noreply(state)
  end

  @doc false
  @impl true
  def handle_cast(
        {:job_starting, _pid, _job_name},
        %{jobs: _jobs} = s
      ) do
    noreply(s)
  end

  @doc false
  @impl true
  def handle_info({:EXIT, pid, _reason} = msg, %{jobs: jobs} = s) do
    if jobs[:running][pid] do
      faults_map = Map.put(jobs[:faults], pid, msg)

      state = put_in(s[:jobs][:faults], faults_map)

      noreply(state)
    else
      noreply(s)
    end
  end

  @doc false
  @impl true
  def handle_info(:timeout, s) do
    import TimeSupport, only: [utc_now: 0]

    schedule_jobs_if_needed(s)
    |> update_last_timeout()
    |> timeout_hook()
  end

  defp job_ending(job_name, measured) do
    GenServer.cast(__MODULE__, {:job_ending, self(), job_name, measured})
  end

  defp job_starting(job_name) do
    GenServer.cast(__MODULE__, {:job_starting, self(), job_name})
  end

  defp make_crontab(time_key) when is_atom(time_key) do
    alias Crontab.CronExpression, as: Cron

    %{hour: hour, month: month, minute: minute, day: day} =
      case time_key do
        :am -> Agnus.sunrise()
        :noon -> Agnus.noon()
        :pm -> Agnus.sunset() |> Timex.shift(hours: -3)
      end

    %Cron{
      extended: false,
      minute: [minute],
      hour: [hour],
      month: [month],
      day: [day]
    }
  end

  defp power_off_if_needed(%{jobs: jobs, opts: opts} = s) do
    if Enum.empty?(jobs[:running]) do
      Map.put(s, :power_off_rc, Switch.off(opts[:power][:device]))
    else
      s
    end
  end

  defp power_on_if_needed(%{jobs: jobs, opts: opts} = s) do
    if Enum.empty?(jobs[:running]) do
      Map.put(s, :power_on_rc, Switch.on(opts[:power][:device]))
    else
      s
    end
  end

  defp schedule_jobs(%{opts: opts} = s) do
    alias Helen.Scheduler
    alias Quantum.Job

    # import Atom, only: [to_string: 1]
    import TimeSupport, only: [utc_now: 0]

    for {job_atom, job_details} <- opts[:jobs],
        {k, schedule} when k == :schedule <- job_details,
        {tod, duration_list} <- schedule do
      job_name =
        ["irrigation", to_string(job_atom), to_string(tod)]
        |> Enum.join("_")
        |> String.to_atom()

      Scheduler.new_job()
      |> Job.set_name(job_name)
      |> Job.set_schedule(make_crontab(tod))
      |> Job.set_task(fn ->
        Irrigation.start_job(job_name, job_atom, tod, duration_list)
      end)
      |> Scheduler.add_job()
    end

    put_in(s[:last_scheduled], utc_now())
  end

  defp schedule_jobs_if_needed(%{last_scheduled: last} = s) do
    import Agnus, only: [current?: 0]
    import TimeSupport, only: [utc_now: 0]
    import Timex, only: [day: 1]

    now = utc_now()

    cond do
      # handles the startup case when Agnus does not yet have info for us
      is_nil(last) and current?() -> schedule_jobs(s)
      # handles the case when it's a new day
      current?() and day(now) > day(last) -> schedule_jobs(s)
      # handles when nothing needs scheduling
      true -> s
    end
  end

  defp spawned_job(job_name, job, _tod, duration, opts) do
    import TimeSupport, only: [list_to_ms: 2]

    power_up_delay_ms = list_to_ms(opts[:power][:power_up_delay], secondd: 0)
    sleep_ms = list_to_ms(duration, seconds: 0)
    device = Keyword.get(opts, job) |> Keyword.get(:device)

    Process.sleep(power_up_delay_ms)

    rc =
      Duration.measure(fn ->
        job_starting(job_name)

        Switch.on(device)

        Process.sleep(sleep_ms)

        Switch.off(device)
      end)

    job_ending(job_name, rc)
  end

  ##
  ## GenServer Receive Loop Hooks
  ##

  defp timeout_hook(%{} = s) do
    state = schedule_jobs_if_needed(s)
    noreply(state)
  end

  ##
  ## State Helpers
  ##

  defp loop_timeout(%{opts: opts}) do
    import TimeSupport, only: [list_to_ms: 2]

    list_to_ms(opts[:timeout], minutes: 1)
  end

  defp update_last_timeout(s) do
    import Agnus.Time.Helper, only: [utc_now: 0]

    put_in(s[:last_timeout], utc_now())
    |> Map.update(:timeouts, 1, &(&1 + 1))
  end

  ##
  ## handle_* return helpers
  ##

  defp noreply(s), do: {:noreply, s, loop_timeout(s)}
  defp reply(val, s), do: {:reply, val, s, loop_timeout(s)}

  defp valid_opts?(state) do
    opts = state[:opts]

    cond do
      is_nil(opts[:jobs]) -> false
      true -> true
    end
  end
end
