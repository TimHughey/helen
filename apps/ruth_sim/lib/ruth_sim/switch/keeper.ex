defmodule SwitchKeeper do
  use Agent

  defstruct known: %{}

  def start_link(_initial_value) do
    Agent.start_link(fn -> %__MODULE__{} end, name: __MODULE__)
  end

  # (1 of 2) freshen request is for SwitchSim
  def freshen(%{type: "pwm"} = ctx) do
    # freshen the device
    ctx
  end

  # (2 of 2) freshen request not for SwitchSim
  def freshen(passthrough), do: passthrough

  def known do
    Agent.get(__MODULE__, fn s -> s.known end)
  end

  def load(dev_name) do
    Agent.get(__MODULE__, fn s ->
      Enum.find(s, fn
        %SwitchSim{device: d} when d == dev_name -> true
        _ -> false
      end)
    end)
  end

  # always used in a pipeline so return the passed arg
  def save(msg) do
    sim = %SwitchSim{
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
