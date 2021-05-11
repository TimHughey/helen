defmodule Alfred.Notify do
  @moduledoc """
  Alfred Notify Public API
  """

  @server Alfred.NotifyServer

  def alive? do
    if GenServer.whereis(@server), do: true, else: false
  end

  def register(name, opts) do
    {:register, name, opts} |> call()
  end

  defp call(msg) do
    if alive?(), do: GenServer.call(@server, msg), else: {:no_server, @server}
  end
end
