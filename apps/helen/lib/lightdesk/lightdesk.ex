defmodule LightDesk do
  @moduledoc """
  Public interface to LightDesk
  """

  alias LightDesk.Server, as: Server

  def mode(val, opts \\ []), do: Server.mode(val, opts)
  def remote_host, do: Server.remote_host()
  def remote_host(new_host), do: Server.remote_host(new_host)

  def state, do: Server.state()
end
