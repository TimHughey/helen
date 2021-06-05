defmodule Garden.Irrigation.Opts do
  @moduledoc false

  def default_opts do
    [
      jobs: [
        flower_boxes: [
          device: "irrigation flower boxes",
          schedule: [am: "PT2M", noon: "PT1M", pm: "PT1M"]
        ],
        garden: [device: "irrigation garden", schedule: [am: "PT10M", noon: "PT5M", pm: "PT10M"]]
      ],
      power: [device: "irrigation 12v power", power_up_delay: "PT5S"],
      device_group: "irrigation",
      timezone: "America/New_York",
      timeout: "PT3M"
    ]
  end
end
