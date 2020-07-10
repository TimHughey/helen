defmodule Garden.Irrigation.Opts do
  alias Helen.Module.Config

  def syntax_version, do: 4

  def create_default_config_if_needed(module) do
    if Config.available?(module) and syntax_version_match?(module) do
      :ok
    else
      Config.create_or_update(module, default_opts(), "auto created defaults")
    end
  end

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

  @doc """
  Reset the module options to defaults as specified in default_opts/0 and restart
  the server.
  """
  def reset_to_defaults(module) do
    Config.create_or_update(module, default_opts(), "reset by api call")
  end

  def syntax_version_match?(module) do
    opts = Config.opts(module)

    if opts[:syntax_vsn] == syntax_version(), do: true, else: false
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
      timezone: "America/New_York",
      timeout: "PT3M"
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
