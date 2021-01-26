defmodule Garden.Irrigation.Opts do
  @moduledoc false

  def default_opts do
    [
      jobs: [],
      power: [device: "irrigation 12v power", power_up_delay: "PT5S"],
      device_group: "irrigation",
      timezone: "America/New_York",
      timeout: "PT3M"
    ]
  end
end
