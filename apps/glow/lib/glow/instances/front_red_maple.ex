defmodule Glow.Instance.FrontRedMaple do
  alias Carol.{Point, Program}

  def init_args(add_args) when is_list(add_args) do
    args = [equipment: "front red maple pwm", programs: programs(), timezone: "America/New_York"]

    Keyword.merge(args, add_args)
  end

  @cmd_opts_common [type: "random", primes: 35, min: 256, step_ms: 55, priority: 7]

  defp fade_bright do
    cmd_opts = Keyword.merge(@cmd_opts_common, max: 768, step: 13)
    [cmd: "fade bright", cmd_opts: cmd_opts]
  end

  defp fade_dim do
    cmd_opts = Keyword.merge(@cmd_opts_common, max: 2048, step: 31)
    [cmd: "fade dim", cmd_opts: cmd_opts]
  end

  defp program(id, start_opts, finish_opts) do
    [Point.new_start(start_opts), Point.new_finish(finish_opts)]
    |> Program.new(id: id)
  end

  defp programs do
    [
      program("Early Evening", [cmd: fade_bright(), sunref: "sunset"], sunref: "astro set"),
      program("Overnight", [cmd: fade_dim(), sunref: "astro set"], sunref: "civil rise")
    ]
  end
end
