defmodule Reef.MixTank.Temp do
  @moduledoc """
  Reef.Temp.Server instance for controlling the mix tank temperature
  """

  use Reef.Temp.Server

  def test_opts do
    opts = [
      switch: [name: "mixtank heater", notify_interval: "PT30S"],
      sensor: [
        name: "mixtank",
        since: "PT2M",
        notify_interval: "PT30S"
      ],
      setpoint: "display_tank",
      offsets: [low: -0.2, high: 0.2]
    ]

    config_update(fn _x -> opts end)
    restart()
  end

  def default_opts do
    opts = [
      switch: [name: "mixtank heater", notify_interval: "PT1M"],
      sensor: [
        name: "mixtank",
        since: "PT2M",
        notify_interval: "PT1M"
      ],
      setpoint: "display_tank",
      offsets: [low: -0.2, high: 0.2]
    ]

    config_update(fn _x -> opts end)
    restart()
  end
end
