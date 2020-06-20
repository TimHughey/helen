defmodule Irrigation.Server do
  @moduledoc """
  Controls the irrigation of Wiss Landing
  """

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
      opts: config_opts(args)
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
    Switch.off_names_begin_with(s[:opts][:device_group])

    # import Crontab.CronExpression

    # schedule(:flower_boxes_am, ~e[0 7 * * *], &flower_boxes/1)
    # schedule(:flower_boxes_noon, ~e[0 12 * * *], &flower_boxes/1, seconds: 15)
    # schedule(:flower_boxes_pm, ~e[20 16 * * *], &flower_boxes/1, seconds: 15)

    noreply(s)
  end

  @doc false
  @impl true
  def handle_call(:state, _from, s), do: reply(s, s)

  @doc false
  @impl true
  def handle_info(:timeout, state) do
    import TimeSupport, only: [utc_now: 0]

    state
    |> update_last_timeout()
    |> timeout_hook()
  end

  # def flower_boxes(opts \\ [seconds: 45]) when is_list(opts) do
  #   irrigate("irrigation flower boxes", opts)
  # end
  #
  # def garden_quick(opts \\ [minutes: 1]) when is_list(opts) do
  #   irrigate("irrigation garden", opts)
  # end
  #
  # def garden(opts \\ [minutes: 30]) when is_list(opts) do
  #   irrigate("irrigation garden", opts)
  # end

  # def irrigate(sw_name, opts) when is_binary(sw_name) and is_list(opts) do
  #   import TimeSupport, only: [list_to_ms: 2]
  #
  #   l_opts = List.flatten(opts)
  #
  #   duration = TimeSupport.duration_from_list(l_opts, seconds: 0)
  #   ms = list_to_ms(l_opts, seconds: 0)
  #
  #   task =
  #     Task.start(fn ->
  #       all_off()
  #
  #       power(:on)
  #       Process.sleep(5000)
  #
  #       """
  #       starting #{sw_name} for #{TimeSupport.humanize_duration(duration)}
  #       """
  #       |> log()
  #
  #       Switch.on(sw_name)
  #
  #       Process.sleep(ms)
  #
  #       Switch.off(sw_name)
  #
  #       power(:off)
  #
  #       # time for switch commands to be acked
  #       Process.sleep(3000)
  #
  #       all_off()
  #
  #       sw_pos = Switch.position(sw_name)
  #
  #       """
  #       finished #{sw_name} power=#{power(:as_binary)} switch=#{inspect(sw_pos)}
  #       """
  #       |> log()
  #     end)
  #
  #   task
  # end

  def power(atom \\ :toggle) when atom in [:on, :off, :toggle, :as_binary] do
    sw = "irrigation 12v power"

    case atom do
      :on ->
        Switch.on(sw)

      :off ->
        Switch.off(sw)

      :toggle ->
        Switch.toggle(sw)

      :as_binary ->
        inspect(Switch.position(sw))
    end
  end

  def schedule(name, crontab, func, opts \\ []) do
    Helen.Scheduler.delete_job(name)

    Helen.Scheduler.new_job()
    |> Quantum.Job.set_name(name)
    |> Quantum.Job.set_schedule(crontab)
    |> Quantum.Job.set_task(fn -> func.(opts) end)
    |> Helen.Scheduler.add_job()
  end

  ##
  ## GenServer Receive Loop Hooks
  ##

  defp timeout_hook(%{} = s) do
    noreply(s)
  end

  ##
  ## State Helpers
  ##

  defp loop_timeout(%{opts: opts}) do
    import TimeSupport, only: [list_to_ms: 2]

    list_to_ms(opts[:timeout], hours: 1)
  end

  defp update_last_timeout(s) do
    import TimeSupport, only: [utc_now: 0]

    %{
      s
      | last_timeout: utc_now(),
        timeouts: Map.update(s, :timeouts, 1, &(&1 + 1))
    }
  end

  ##
  ## handle_* return helpers
  ##

  defp noreply(s), do: {:noreply, s, loop_timeout(s)}
  defp reply(val, s), do: {:reply, val, s, loop_timeout(s)}

  defp valid_opts?(state) do
    opts = state[:opts]

    cond do
      is_nil(opts[:flower_boxes]) -> false
      is_nil(opts[:garden]) -> false
      true -> true
    end
  end
end
