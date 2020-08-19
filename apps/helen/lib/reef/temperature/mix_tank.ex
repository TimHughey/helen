defmodule Reef.MixTank.Temp do
  @moduledoc """
  Reef.Temp.Server instance for controlling the mix tank temperature
  """

  use Reef.Temp.Server

  def default_opts do
    [
      server_mode: :standby,
      switch: [name: "mixtank heater", notify_interval: "PT1M"],
      sensor: [
        name: "mixtank",
        since: "PT2M",
        notify_interval: "PT1M"
      ],
      setpoint: "display_tank",
      offsets: [low: -0.2, high: 0.2]
    ]
  end
end
