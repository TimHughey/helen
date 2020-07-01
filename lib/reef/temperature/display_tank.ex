defmodule Reef.DisplayTank.Temp do
  @moduledoc """
  Reef.Temp.Server instance for controlling the display tank temperature
  """

  use Reef.Temp.Server

  def test_opts do
    opts = [
      switch: [name: "display tank heater", notify_interval: "PT1M"],
      sensor: [
        name: "display_tank",
        since: "PT2M",
        notify_interval: "PT1M"
      ],
      setpoint: 75.0,
      offsets: [low: -0.2, high: 0.2]
    ]

    config_update(fn _x -> opts end)
    restart()
  end

  def default_opts do
    opts = [
      switch: [name: "display tank heater", notify_interval: "PT1M"],
      sensor: [
        name: "display_tank",
        since: "PT2M",
        notify_interval: "PT1M"
      ],
      setpoint: 75.0,
      offsets: [low: -0.2, high: 0.2]
    ]

    config_update(fn _x -> opts end)
    restart()
  end
end
