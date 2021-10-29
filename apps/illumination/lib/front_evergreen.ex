defmodule FrontEvergreen do
  use Illumination, shutdown: 10_000

  def start_args do
    alias Illumination.Schedule
    alias Illumination.Schedule.Point

    [
      equipment: "front evergreen pwm",
      schedules: [
        %Schedule{
          id: "early evening",
          start: %Point{sunref: "civil set", cmd: "fade_bright"},
          finish: %Point{sunref: "astro set"}
        },
        %Schedule{
          id: "overnight",
          start: %Point{sunref: "astro set", cmd: "fade_dim"},
          finish: %Point{sunref: "civil rise"}
        }
      ],
      cmds: %{
        "fade_bright" => [
          type: "random",
          min: 256,
          max: 2048,
          primes: 35,
          step_ms: 55,
          step: 31,
          priority: 7
        ],
        "fade_dim" => [
          type: "random",
          min: 256,
          max: 1024,
          primes: 35,
          step_ms: 55,
          step: 13,
          priority: 7
        ]
      },
      timezone: "America/New_York"
    ]
  end
end
