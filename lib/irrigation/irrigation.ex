defmodule Irrigation do
  @moduledoc """
    Irrigation Implementation for Wiss Landing
  """
  # use Timex
  # import Crontab.CronExpression
  #
  # def all_off do
  #   Switch.names_begin_with("irrigation") |> Switch.off()
  #
  #   """
  #   ensuring all switches are off
  #   """
  #   |> log()
  #
  #   Process.sleep(3000)
  # end
  #
  #
  #
  # def init(opts \\ []) when is_list(opts) do
  #   switches = (opts ++ ["irrigation"]) |> List.flatten()
  #   for n <- switches, do: Switch.names_begin_with(n) |> Switch.off()
  #
  #
  #
  #   Keeper.put_key(:irrigate, "")
  #   log("initialized")
  #
  #   :ok
  # end
  #
  #
  # def status do
  #   log = Keeper.get_key(:irrigate)
  #
  #   IO.puts(log)
  # end
  #
  # defp log(msg) do
  #   ts = Timex.local() |> Timex.format!("{YYYY}-{0M}-{D} {h24}:{m}")
  #   msg = "#{ts} #{msg}"
  #
  #   log = Keeper.get_key(:irrigate)
  #
  #   new_log = Enum.join([log, msg], "")
  #
  #   Keeper.put_key(:irrigate, new_log)
  # end
end
