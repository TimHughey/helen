defmodule Garden.Lighting.Opts do
  @moduledoc false

  def default_opts do
    [
      syntax_vsn: "2020-0818",
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
            step: 31,
            priority: 7
          }
        },
        random_fade_dim: %{
          name: "fade dim",
          random: %{
            min: 256,
            max: 1024,
            primes: 35,
            step_ms: 55,
            step: 13,
            priority: 7
          }
        }
      ],
      jobs: [
        indoor_garden_alpha: [
          device: "indoor garden alpha",
          schedule: [
            day: [
              sun_ref: :nautical_twilight_begin,
              before: "PT0S",
              cmd: :on
            ],
            night: [
              sun_ref: :nautical_twilight_begin,
              after: "PT16H",
              cmd: :off
            ]
          ]
        ],
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
end
