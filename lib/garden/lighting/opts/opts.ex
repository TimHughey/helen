defmodule Garden.Lighting.Opts do
  alias Helen.Module.Config

  def syntax_version, do: "2020-0710"

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
      timeout: "PT3M",
      timezone: "America/New_York",
      cmd_definitions: [
        random_fade_bright: %{
          name: "fade bright",
          random: %{
            min: 256,
            max: 2048,
            primes: 35,
            step_ms: 55,
            step: 13,
            priority: 7
          }
        },
        random_fade_dim: %{
          name: "fade dim",
          random: %{
            min: 64,
            max: 1024,
            primes: 35,
            step_ms: 55,
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
              before: "PT0S",
              cmd: :off
            ],
            evening: [
              sun_ref: :sunset,
              after: "PT0S",
              cmd: :random_fade_bright
            ],
            night: [
              sun_ref: :civil_twilight_end,
              after: "PT0S",
              cmd: :random_fade_dim
            ]
          ]
        ],
        red_maple: [
          device: "front leds red maple",
          schedule: [
            morning: [
              sun_ref: :civil_twilight_begin,
              before: "PT0S",
              cmd: :off
            ],
            evening: [
              sun_ref: :sunset,
              after: "PT0S",
              cmd: :random_fade_bright
            ],
            night: [
              sun_ref: :civil_twilight_end,
              after: "PT0S",
              cmd: :random_fade_dim
            ]
          ]
        ],
        evergreen: [
          device: "front leds evergreen",
          schedule: [
            morning: [
              sun_ref: :civil_twilight_begin,
              before: "PT0S",
              cmd: :off
            ],
            evening: [
              sun_ref: :sunset,
              after: "PT0S",
              cmd: :random_fade_bright
            ],
            night: [
              sun_ref: :civil_twilight_end,
              after: "PT0S",
              cmd: :random_fade_dim
            ]
          ]
        ]
      ]
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
