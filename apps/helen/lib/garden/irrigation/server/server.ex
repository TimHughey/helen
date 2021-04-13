defmodule Garden.Irrigation.Server do
  @moduledoc """
  Controls the irrigation of Wiss Landing
  """

  use Timex
  use GenServer, restart: :transient, shutdown: 7000

  ##
  ## GenServer Start and Initialization
  ##

  @doc false
  @impl true
  def init(args) do
    import Helen.Time.Helper, only: [epoch: 0]
    import Garden.Irrigation.Opts, only: [default_opts: 0]

    state = %{
      server_mode: args[:server_mode] || :active,
      last_timeout: epoch(),
      timeouts: 0,
      opts: default_opts(),
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

  @doc false
  def last_timeout do
    import Helen.Time.Helper, only: [epoch: 0, utc_now: 0]

    with last <- x_state(:last_timeout),
         d when d > 0 <- Timex.diff(last, epoch()) do
      last
    else
      _epoch -> epoch()
    end
  end

  @doc """
  Return the number of GenServer timeouts.

  Timeouts are expected and appropriate for Irrigation.Server.  An increasing
  number of timeouts indicates the server is primarily waiting for either
  a message to start a job or messages from jobs ending.
  """
  @doc since: "0.0.27"
  def timeouts, do: x_state() |> Map.get(:timeouts)

  @doc """
  Restarts the server via the Supervisor

  ## Examples

      iex> Irrigation.Server.restart([])
      :ok

  """
  @doc since: "0.0.27"
  def restart(opts \\ []) do
    # the Supervisor is the first part of the module
    [sup_base | _remainder] = Module.split(__MODULE__)

    sup_mod = Module.concat([sup_base, "Supervisor"])

    if GenServer.whereis(__MODULE__) do
      Supervisor.terminate_child(sup_mod, __MODULE__)
    end

    Supervisor.delete_child(sup_mod, __MODULE__)
    Supervisor.start_child(sup_mod, {__MODULE__, opts})
  end

  @doc """
    Raw access to the start job functionality.  You have been warned.

    iex> Irrigation.Server.start_job(job_name, job_atom, tod_atom, duration_list)
    :ok

  """
  @doc since: "0.0.27"
  def start_job(job_name, job_atom, tod_atom, duration_list) do
    GenServer.cast(
      __MODULE__,
      {:start_job, job_name, job_atom, tod_atom, duration_list}
    )
  end

  @doc """
  Return the server state (for diagnostic purposes)
  """
  @doc since: "0.0.27"
  def x_state(keys \\ []) do
    keys = [keys] |> List.flatten()
    state = GenServer.call(__MODULE__, :state)

    case keys do
      [] -> state
      [x] -> Map.get(state, x)
      x -> Map.take(state, [x])
    end
  end

  ##
  ## GenServer handle_* callbacks
  ##

  @doc false
  @impl true
  def handle_continue(:bootstrap, %{server_mode: mode} = s) do
    Process.flag(:trap_exit, true)

    Switch.off_names_begin_with(s[:opts][:device_group])

    if mode == :active do
      # NOTE:
      #  schedule_jobs_if_needed/1 handles the possible race condition / delay
      #  related to Agnus acquiring sun info at start up.  if sun info isn't
      #  available yet scheduling is attempted at the next timeout.
      s |> schedule_jobs_if_needed() |> noreply
    else
      noreply(s)
    end
  end

  @doc false
  @impl true
  def handle_call(:state, _from, s), do: reply(s, s)

  @doc false
  @impl true
  def handle_cast(
        {:start_job, job_name, job, tod, d},
        %{opts: opts} = state
      ) do
    alias Helen.Scheduler

    # spawn the job, it will wait for the configured power up delay
    # before starting
    pid = spawn_link(fn -> spawned_job(job_name, job, tod, d, opts) end)

    # power up the +12v for the valves
    state
    |> power_on_if_needed()
    |> put_in([:jobs, :running, pid], job_name)
    |> noreply()
  end

  @doc false
  @impl true
  def handle_cast({:job_ending, pid, job_name, last_rc}, state) do
    alias Helen.Scheduler

    # remove the job from the running map
    state
    |> update_in([:jobs, :running], fn x -> Map.drop(x, [pid]) end)
    |> update_in([:jobs, :last_rc, job_name], fn
      nil -> %{}
      x -> x
    end)
    |> put_in([:jobs, :last_rc, job_name], last_rc)
    |> power_off_if_needed()
    |> noreply()
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
    import Helen.Time.Helper, only: [utc_now: 0]

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
    import Helen.Time.Helper, only: [local_now: 1]

    # iterate through the keyword list :jobs from the opts selecting only
    # the key :schedule
    for {job_atom, job_details} <- opts[:jobs],
        {k, schedule} when k == :schedule <- job_details do
      # for this job, iterate through the key/value pairs of time-of-day and
      # duration options to schedule each job
      for {tod, duration_list} <- schedule do
        job_name =
          ["irrigation", to_string(job_atom), to_string(tod)]
          |> Enum.join("_")
          |> String.to_atom()

        Scheduler.delete_job(job_name)

        Scheduler.new_job()
        |> Job.set_name(job_name)
        |> Job.set_schedule(make_crontab(tod))
        |> Job.set_timezone(opts[:timezone])
        |> Job.set_task(fn ->
          Irrigation.start_job(job_name, job_atom, tod, duration_list)
        end)
        |> Scheduler.add_job()
      end
    end

    put_in(s[:last_scheduled], local_now(opts[:timezone]))
  end

  defp schedule_jobs_if_needed(%{last_scheduled: last, opts: opts} = s) do
    import Agnus, only: [current?: 0]
    import Helen.Time.Helper, only: [local_now: 1]
    import Timex, only: [day: 1]

    now = local_now(opts[:timezone])

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
    import Helen.Time.Helper, only: [to_ms: 2]

    power_up_delay_ms = to_ms(opts[:power][:power_up_delay], "PT0S")
    sleep_ms = to_ms(duration, "PT0S")
    device = Keyword.get(opts[:jobs], job) |> Keyword.get(:device)

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

  defp timeout_hook(state) do
    state |> schedule_jobs_if_needed() |> noreply()
  end

  ##
  ## State Helpers
  ##

  defp loop_timeout(%{opts: opts}) do
    import Helen.Time.Helper, only: [to_ms: 2]

    to_ms(opts[:timeout], "PT1M")
  end

  defp update_last_timeout(s) do
    import Helen.Time.Helper, only: [utc_now: 0]

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

    if is_nil(opts[:jobs]), do: false, else: true
  end
end
