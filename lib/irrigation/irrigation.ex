defmodule Irrigation do
  @moduledoc """
    Irrigation Implementation for Wiss Landing
  """

  alias Irrigation.Server

  @doc delegate_to: {Server, :start_job, 1}
  defdelegate start_job(job_name, job_atom, tod_atom, duration_list),
    to: Server

  def front_porch_oneshot(opts \\ [seconds: 45]) do
    Server.start_job(:garden_oneshot, :garden, :oneshot, opts)
  end

  def garden_oneshot(opts \\ [minutes: 30]) do
    Server.start_job(:garden_oneshot, :garden, :oneshot, opts)
  end

  @doc false
  defdelegate state, to: Server
end
