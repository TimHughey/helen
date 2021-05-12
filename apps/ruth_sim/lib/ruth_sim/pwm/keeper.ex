defmodule PwmKeeper do
  use Agent

  defstruct known: %{}

  def start_link(_) do
    Agent.start_link(fn -> MapSet.new() end, name: __MODULE__)
  end

  # (1 of 3) freshen a PwmSim
  def freshen(%PwmSim{} = sim) do
    %{sim | mtime: System.os_time(:second)} |> save()
  end

  # (2 of 3) find the device from a ctx, freshen it then put in the ctx for pipeline
  def freshen(%{tyep: "pwm", device: device} = ctx) when is_map(ctx) do
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
        %PwmSim{device: d} when d == dev_name -> true
        _ -> false
      end)
    end)
  end

  def save(%PwmSim{} = sim) do
    Agent.update(__MODULE__, fn s -> MapSet.put(s, sim) end)
    sim
  end

  # always used in a pipeline so return the passed arg
  def save(msg) do
    sim = %PwmSim{
      device: msg.device,
      host: msg.host,
      mtime: msg.mtime,
      pio_count: msg.pio_count,
      states: msg.states
    }

    Agent.update(__MODULE__, fn s -> MapSet.put(s, sim) end)
    msg
  end
end
