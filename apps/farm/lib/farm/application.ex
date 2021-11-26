defmodule Farm.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Rena.SetPt.Server, womb_setpt_args()},
      {Rena.HoldCmd.Server, womb_circulation_args()}
    ]

    opts = [strategy: :one_for_one, name: Farm.Supervisor, max_restarts: 10, max_seconds: 10]
    Supervisor.start_link(children, opts)
  end

  def womb_circulation_args do
    alias Alfred.ExecCmd

    hold_cmd = %ExecCmd{cmd: "25% of max", cmd_params: %{type: "fixed", percent: 25}}
    [id: Farm.Womb.Circulation, hold_cmd: hold_cmd, equipment: "womb circulation pwm"]
  end

  def womb_setpt_args do
    alias Rena.Sensor.Range

    sensors = ["womb 1", "womb 2", "womb 3", "womb 4"]
    range = %Range{low: 78.0, high: 80.1, unit: :temp_f}
    [id: Farm.Womb.Heater, equipment: "womb heater power", sensors: sensors, range: range]
  end
end
