defmodule Farm.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Rena.SetPt.Server, [id: Farm.Womb.Heater, init_args_fn: &womb_setpt_args/1]},
      {Rena.HoldCmd.Server, [id: Farm.Womb.Circulation, init_args_fn: &womb_circulation_args/1]}
    ]

    opts = [strategy: :one_for_one, name: Farm.Supervisor, max_restarts: 10, max_seconds: 10]
    Supervisor.start_link(children, opts)
  end

  def womb_circulation_args(add_args) do
    alias Alfred.ExecCmd

    hold_cmd = %ExecCmd{cmd: "25% of max", cmd_params: %{type: "fixed", percent: 25}}

    [hold_cmd: hold_cmd, equipment: "womb circulation pwm"]
    |> Keyword.merge(add_args)
  end

  def womb_setpt_args(add_args) do
    sensors = ["womb 1", "womb 2", "womb 3", "womb 4"]
    range = [low: 78.0, high: 80.1]

    [equipment: "womb heater power", sensors: sensors, sensor_range: range]
    |> Keyword.merge(add_args)
  end
end
