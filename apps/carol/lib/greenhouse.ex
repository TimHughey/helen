defmodule Greenhouse do
  def start_args do
    alias Carol.Schedule
    alias Carol.Schedule.Point

    [
      module: __MODULE__,
      equipment: "greenhouse alpha power",
      schedules: [
        %Schedule{
          id: "daylight",
          start: %Point{sunref: "astro rise", cmd: "on"},
          finish: %Point{sunref: "astro rise", offset_ms: 16 * 60 * 60 * 1000}
        }
      ],
      timezone: "America/New_York"
    ]
  end
end
