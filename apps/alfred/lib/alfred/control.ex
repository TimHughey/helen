defmodule Alfred.Control do
  @moduledoc """
  Alfred Control Public API
  """

  @server Alfred.Control.Server

  def alive? do
    if GenServer.whereis(@server), do: true, else: false
  end
end
