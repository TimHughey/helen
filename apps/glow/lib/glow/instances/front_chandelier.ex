# defmodule Glow.FrontChandelier do
#   alias Carol.{Point, Program}
#
#   @equipment "front chandelier pwm"
#   @tz "America/New_York"
#
#   def init_args(add_args) when is_list(add_args) do
#     args = [equipment: @equipment, programs: programs(), timezone: @tz]
#
#     Keyword.merge(args, add_args)
#   end
#
#   @cmd_params_common [type: "random", priority: 7, primes: 8, step: 6, step_ms: 40]
#
#   ## PRIVATE
#   ## PRIVATE
#   ## PRIVATE
#
#   defp cmd(what) do
#     case what do
#       :evening -> [min: 384, max: 1024]
#       :overnight -> [min: 175, max: 640]
#     end
#     |> then(fn cmd_params -> Keyword.merge(@cmd_params_common, cmd_params) end)
#     |> then(fn final_params -> [cmd: Atom.to_string(what), cmd_params: final_params] end)
#   end
#
#   defp program(id, start_opts, finish_opts) do
#     [Point.new_start(start_opts), Point.new_finish(finish_opts)]
#     |> Program.new(id: id)
#   end
#
#   defp programs do
#     [
#       program("Early Evening", [cmd: cmd(:evening), sunref: "sunset"], sunref: "astro set"),
#       program("Overnight", [cmd: cmd(:overnight), sunref: "astro set"], sunref: "civil rise")
#     ]
#   end
# end
