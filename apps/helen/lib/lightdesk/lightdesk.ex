defmodule LightDesk do
  @moduledoc """
  Public interface to LightDesk
  """

  alias LightDesk.Server, as: Server

  def mode(val, opts \\ []) do
    case val do
      :dance -> Server.mode(:dance, interval_secs: 23.3)
      :ready -> Server.mode(:ready, opts)
      :stop -> Server.mode(:stop, opts)
    end
  end

  def remote_host, do: Server.remote_host()
  def remote_host(new_host), do: Server.remote_host(new_host)

  def state, do: Server.state()
end
