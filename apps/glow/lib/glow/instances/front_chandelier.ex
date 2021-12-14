defmodule Glow.FrontChandelier do
  alias Carol.{Point, Program}

  @equipment "front chandelier pwm"
  @tz "America/New_York"

  def init_args(add_args) when is_list(add_args) do
    args = [equipment: @equipment, programs: programs(), timezone: @tz]

    Keyword.merge(args, add_args)
  end

  @cmd_params_common [type: "random", primes: 35, min: 256, step_ms: 33, priority: 7]

  defp fade_bright do
    cmd_params = Keyword.merge(@cmd_params_common, max: 1024, step: 23)
    [cmd: "fade bright", cmd_params: cmd_params]
  end

  defp fade_dim do
    cmd_params = Keyword.merge(@cmd_params_common, max: 768, step: 13)
    [cmd: "fade dim", cmd_params: cmd_params]
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
