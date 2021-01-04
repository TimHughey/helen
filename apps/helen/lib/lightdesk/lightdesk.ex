defmodule LightDesk do
  @moduledoc """
  Public interface to LightDesk
  """

  alias LightDesk.Server, as: Server

  def dance, do: dance("roost-beta", 23.3)

  def dance(remote, interval \\ 23.3)
      when is_integer(remote) or (is_binary(remote) and is_number(interval)) do
    Server.dance(remote, interval)
  end

  def mode(val) do
    case val do
      :dance -> dance()
      :pause -> pause()
    end
  end

  def mode_ready(remote), do: Server.mode(remote, :ready)
  def mode_pause(remote), do: Server.mode(remote, :pause)

  def pause, do: mode_pause("roost-beta")

  def state, do: Server.state()
end
