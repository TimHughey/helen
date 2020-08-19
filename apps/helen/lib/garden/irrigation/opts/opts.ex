defmodule Garden.Irrigation.Opts do
  @moduledoc false

  def default_opts do
    [
      jobs: [
        flower_boxes: [
          device: "irrigation flower boxes",
          schedule: [am: "PT45S", noon: "PT30S", pm: "PT30S"]
        ],
        garden: [device: "irrigation garden", schedule: [am: "PT30M"]]
      ],
      power: [device: "irrigation 12v power", power_up_delay: "PT5S"],
      device_group: "irrigation",
      timezone: "America/New_York",
      timeout: "PT3M"
    ]
  end
end
