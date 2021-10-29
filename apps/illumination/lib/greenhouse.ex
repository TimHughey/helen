defmodule Greenhouse do
  use Illumination, shutdown: 10_000

  def start_args do
    alias Illumination.Schedule
    alias Illumination.Schedule.Point

    [
      id: "daylight",
      equipment: "greenhouse alpha power",
      schedules: [
        %Schedule{
          start: %Point{sunref: "astro rise", cmd: "on"},
          finish: %Point{sunref: "astro rise", offset_ms: 16 * 60 * 60 * 1000}
        }
      ],
      timezone: "America/New_York"
    ]
  end
end
