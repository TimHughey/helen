defmodule Garden.Lighting.Opts do
  alias Helen.Module.Config

  def create_default_config_if_needed(module) do
    if Config.available?(module) and syntax_version_match?(module) do
      :ok
    else
      Config.create_or_update(module, default_opts(), "auto created defaults")
    end
  end

  def default_opts do
    [
      syntax_vsn: syntax_version(),
      timeout: "PT1M",
      timezone: "America/New_York",
      cmd_definitions: [
        random_fade_bright: %{
          name: "slow fade",
          random: %{
            min: 256,
            max: 2048,
            primes: 25,
            step_ms: 50,
            step: 3,
            priority: 7
          }
        },
        random_fade_dim: %{
          name: "slow fade",
          random: %{
            min: 128,
            max: 1024,
            primes: 15,
            step_ms: 50,
            step: 3,
            priority: 7
          }
        }
      ],
      jobs: [
        porch: [
          device: "front leds porch",
          schedule: [
            morning: [
              sun_ref: :civil_twilight_begin,
              before: "PT30M",
              cmd: :off
            ],
            evening: [
              sun_ref: :sunset,
              after: "PT0S",
              cmd: :random_fade_bright
            ],
            night: [
              sun_ref: :sunset,
              after: "PT1H30M",
              cmd: :random_fade_dim
            ]
          ]
        ],
        red_maple: [
          device: "front leds red maple",
          schedule: [
            morning: [
              sun_ref: :civil_twilight_begin,
              before: "PT30M",
              cmd: :off
            ],
            evening: [
              sun_ref: :sunset,
              after: "PT0S",
              cmd: :random_fade_bright
            ],
            night: [
              sun_ref: :sunset,
              after: "PT1H30M",
              cmd: :random_fade_dim
            ]
          ]
        ],
        evergreen: [
          device: "front leds evergreen",
          schedule: [
            morning: [
              sun_ref: :civil_twilight_begin,
              before: "PT30M",
              cmd: :off
            ],
            evening: [
              sun_ref: :sunset,
              after: "PT0S",
              cmd: :random_fade_bright
            ],
            night: [
              sun_ref: :sunset,
              after: "PT1H30M",
              cmd: :random_fade_dim
            ]
          ]
        ]
      ]
    ]
  end

  def syntax_version, do: 2

  def syntax_version_match?(module) do
    opts = Config.opts(module)

    if opts[:syntax_version] == syntax_version(), do: true, else: false
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
