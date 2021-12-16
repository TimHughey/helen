defmodule Glow.FrontChandelier do
  alias Carol.{Point, Program}

  @equipment "front chandelier pwm"
  @tz "America/New_York"

  def init_args(add_args) when is_list(add_args) do
    args = [equipment: @equipment, programs: programs(), timezone: @tz]

    Keyword.merge(args, add_args)
  end

  @cmd_params_common [type: "random", priority: 7]

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  defp assemble_cmd_opts(cmd_params, cmd_name) do
    @cmd_params_common
    |> Keyword.merge(cmd_params)
    |> then(fn final_params -> [cmd: cmd_name, cmd_params: final_params] end)
  end

  defp fade_bright do
    [min: 384, max: 1024, primes: 8, step: 33, step_ms: 33]
    |> assemble_cmd_opts("fade bright")
  end

  defp fade_dim do
    [min: 175, max: 512, primes: 8, step: 5, step_ms: 40]
    |> assemble_cmd_opts("fade dim")
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
