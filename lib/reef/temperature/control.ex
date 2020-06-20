defmodule Reef.Temp.Control do
  @moduledoc """
  Controls the temperature of an environment using the readings of a
  Sensor to control a Switch
  """

  use GenServer, restart: :transient, shutdown: 7000

  use Helen.Module.Config

  alias Sensor.DB.Alias, as: SensorAlias
  alias Switch.DB.Alias, as: SwitchAlias

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
      devices: %{}
    }

    if is_nil(state[:opts][:sensor]) or is_nil(state[:opts][:switch]),
      do: :ignore,
      else: {:ok, state, {:continue, :bootstrap}}
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

  def temperature, do: GenServer.call(__MODULE__, :temperature)

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
    Supervisor.terminate_child(Reef.Supervisor, __MODULE__)
    Supervisor.restart_child(Reef.Supervisor, __MODULE__)
  end

  ##
  ## GenServer handle_* callbacks
  ##

  @doc false
  @impl true
  def handle_call(:temperature, _from, s) do
    {temperature, state} = sensor_temperature(s)

    reply(temperature, state)
  end

  @doc false
  @impl true
  def handle_call(:state, _from, s), do: reply(s, s)

  @doc false
  @impl true
  def handle_continue(:bootstrap, s) do
    Switch.notify_register(s[:opts][:switch])
    Sensor.notify_register(s[:opts][:sensor])

    noreply(s)
  end

  @doc false
  @impl true
  def handle_info(
        {:notify, :sensor, %SensorAlias{name: n} = obj},
        %{opts: opts, devices: devices} = s
      ) do
    cond do
      n == opts[:sensor][:name] ->
        import TimeSupport, only: [utc_now: 0]
        import Sensor, only: [fahrenheit: 2]

        entry = %{
          obj: obj,
          seen: utc_now(),
          temperature: fahrenheit(n, sensor_opts(opts))
        }

        %{s | devices: Map.put(devices, n, entry)} |> noreply()

      true ->
        noreply(s)
    end
  end

  @doc false
  @impl true
  def handle_info(
        {:notify, :switch, %SwitchAlias{name: n} = obj},
        %{opts: opts, devices: devices} = s
      ) do
    cond do
      n == opts[:switch][:name] ->
        import TimeSupport, only: [utc_now: 0]
        import Switch, only: [position: 1]

        entry = %{
          obj: obj,
          seen: utc_now(),
          position: position(n)
        }

        %{s | devices: Map.put(devices, n, entry)} |> noreply()

      true ->
        noreply(s)
    end
  end

  @doc false
  @impl true
  def handle_info(:timeout, state) do
    import TimeSupport, only: [utc_now: 0]

    state
    |> update_last_timeout()
    |> timeout_hook()
  end

  ##
  ## GenServer Receive Loop Hooks
  ##

  defp timeout_hook(%{} = s) do
    noreply(s)
  end

  ##
  ## PRIVATE
  ##

  defp sensor_opts(x) do
    # handle if passed an opts keyword list or the state
    # if not found in either then default to 30 seconds
    x[:sensor] || x[:opts][:sensor] || [since: [seconds: 30]]
  end

  defp sensor_temperature(%{opts: opts} = s) do
    import Sensor, only: [fahrenheit: 2]

    # if there is any issue with getting the Sensor value store the
    # issue in the state under key :sensor_fault so other functions can
    # take action as needed
    with {:name, n} when is_binary(n) <- {:name, opts[:sensor][:name]},
         temp when is_number(temp) <- fahrenheit(n, sensor_opts(opts)) do
      {temp, Map.drop(s, [:sensor_fault])}
    else
      {:name, n} -> {:failed, Map.put(s, :sensor_fault, {:name_not_binary, n})}
      rc -> {rc, Map.put(s, :sensor_fault, rc)}
    end
  end

  ##
  ## State Helpers
  ##

  defp loop_timeout(%{}), do: 5 * 60 * 1000

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
end
