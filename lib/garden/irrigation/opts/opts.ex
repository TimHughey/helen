defmodule Garden.Irrigation.Opts do
  alias Helen.Module.Config

  def create_default_config_if_needed(module) do
    if Config.available?(module) do
      nil
    else
      opts = [
        jobs: [
          flower_boxes: [
            device: "irrigation flower boxes",
            schedule: [am: "PT45S", noon: "PT30S", pm: "PT30S"]
          ],
          garden: [device: "irrigation garden", schedule: [am: "PT30M"]]
        ],
        power: [device: "irrigation 12v power", power_up_delay: "PT5S"],
        device_group: "irrigation",
        timezone: "America/New_York"
      ]

      Config.create_or_update(module, opts, "auto created defaults")
    end
  end

  def test_opts do
    opts = [
      jobs: [
        flower_boxes: [
          device: "irrigation flower boxes",
          schedule: [am: "PT45S", noon: "PT30S", pm: "PT30S"]
        ],
        garden: [device: "irrigation garden", schedule: [am: "PT30M"]]
      ],
      power: [device: "irrigation 12v power", power_up_delay: "PT5S"],
      device_group: "irrigation",
      timezone: "America/New_York"
    ]

    Config.create_or_update(module(), opts, "test opts")
  end

  defp module do
    # drop the last part of this module (e.g.) to create the name of the module
    # these opts are for
    mod_parts = Module.split(__MODULE__)
    num_parts = length(mod_parts)

    [Enum.take(mod_parts, num_parts - 1), Server]
    |> List.flatten()
    |> Module.concat()
  end
end
