defmodule SensorKeeper do
  use Agent

  defstruct known: %{}

  # (1 of 3) freshen a SensorSim
  def freshen(%SensorSim{} = sim) do
    %{sim | mtime: System.os_time(:second)} |> save()
  end

  # (2 of 3) find the device from a ctx, freshen it then put in the ctx for pipeline
  def freshen(%{tyep: "sensor", device: device} = ctx) when is_map(ctx) do
    sim = load(device) |> freshen()

    put_in(ctx, [:sim], sim)
  end

  def freshen(passthrough), do: passthrough

  def known do
    Agent.get(__MODULE__, fn s -> MapSet.to_list(s) end)
  end

  def load(dev_name) do
    Agent.get(__MODULE__, fn s ->
      Enum.find(s, fn
        %SensorSim{device: d} when d == dev_name -> true
        _ -> false
      end)
    end)
  end

  # (1 of 2) save a SensorSim
  def save(%SensorSim{} = sim) do
    Agent.update(__MODULE__, fn s -> MapSet.put(s, sim) end)

    sim
  end

  # (2 of 2) save a SensorSim from a msg pipeline
  def save(msg) do
    sim = %SensorSim{
      device: msg.device,
      host: msg.host,
      mtime: msg.mtime,
      datapoint: msg.datapoint
    }

    Agent.update(__MODULE__, fn s -> MapSet.put(s, sim) end)
    msg
  end

  def start_link(_) do
    Agent.start_link(fn -> MapSet.new() end, name: __MODULE__)
  end
end
