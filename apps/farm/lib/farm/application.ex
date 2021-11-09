defmodule Farm.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      womb()
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Farm.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def womb do
    alias Rena.Sensor.Range

    sensors = ["womb 1", "womb 2", "womb 3", "womb 4"]
    range = %Range{low: 78.0, high: 80.1, unit: :temp_f}
    args = [name: Farm.Womb, equipment: "womb heater power", sensors: sensors, range: range]

    %{id: Farm.Womb, start: {Rena.SetPt.Server, :start_link, [args]}, restart: :transient}
  end
end
