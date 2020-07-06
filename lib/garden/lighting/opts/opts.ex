defmodule Garden.Lighting.Opts do
  alias Helen.Module.Config

  def create_default_config_if_needed(module) do
    if Config.available?(module) do
      nil
    else
      opts = [
        timeout: "PT1M",
        jobs: [
          porch: [
            device: "front leds porch",
            schedule: [
              morning: [
                reference: :civil_twilight_begin,
                before: "PT1H",
                duty: 0
              ],
              evening: [
                reference: :civil_twilight_end,
                after: "PT15M",
                duty: 0.3
              ]
            ]
          ],
          red_maple: [
            device: "front leds red maple",
            schedule: [
              morning: [reference: :civil_twilight_end, before: "PT1H", duty: 0],
              evening: [reference: :civil_twilight_begin, after: "PT15M"]
            ]
          ]
        ]
      ]

      Config.create_or_update(module, opts, "auto created defaults")
    end
  end

  def test_opts do
    opts = []

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
