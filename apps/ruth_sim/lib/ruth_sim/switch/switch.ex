defmodule SwitchSim do
  use Agent

  @default_device "switch/simulated"
  @pios 12

  @default_states for x <- 0..(@pios - 1), do: %{pio: x, state: false}

  defstruct device: @default_device,
            host: RemoteSim.default_host(),
            mtime: EasyTime.unix_now(:second),
            pio_count: @pios,
            states: @default_states

  def default_device, do: @default_device

  def default_states, do: @default_states

  def populate_device(msg, ctx) do
    put_in(msg, [:device], ctx[:device] || default_device())
  end

  def populate_states(msg, ctx \\ []) do
    states = ctx[:states] || default_states()
    pio_count = length(states)

    msg
    |> put_in([:states], states)
    |> put_in([:pio_count], pio_count)
  end
end
