defmodule Irrigation do
  @moduledoc """
    Irrigation Implementation for Wiss Landing
  """

  alias Irrigation.Server

  @doc delegate_to: {Server, :start_job, 1}
  defdelegate start_job(job_name, job_atom, tod_atom, duration_list),
    to: Server

  def garden_short(opts \\ [minutes: 11]) do
    Server.start_job(:garden_short, :garden, :oneshot, opts)
  end

  @doc false
  defdelegate state, to: Server

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
