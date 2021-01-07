defmodule LightDesk do
  @moduledoc """
  Public interface to LightDesk
  """

  alias LightDesk.Server, as: Server

  def mode(val) do
    case val do
      :dance -> Server.mode(:dance)
      :ready -> Server.mode(:ready)
      :stop -> Server.mode(:stop)
    end
  end

  def remote_host, do: Server.remote_host()
  def remote_host(new_host), do: Server.remote_host(new_host)

  def state, do: Server.state()
end
