defmodule Glow.Greenhouse do
  alias Carol.{Point, Program}

  def init_args(add_args) when is_list(add_args) do
    args = [
      equipment: "greenhouse alpha power",
      programs: programs(),
      timezone: "America/New_York"
    ]

    Keyword.merge(args, add_args)
  end

  defp program(id, start_opts, finish_opts) do
    [Point.new_start(start_opts), Point.new_finish(finish_opts)]
    |> Program.new(id: id)
  end

  defp programs do
    [
      program("Daylight", [sunref: "astro rise"],
        sunref: "astro rise",
        offset_ms: 16 * 60 * 60 * 1000
      )
    ]
  end
end
