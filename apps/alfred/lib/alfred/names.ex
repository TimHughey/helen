defmodule Alfred.Names do
  @moduledoc """
  Alfred Names Public API
  """

  alias Alfred.JustSaw

  @server Alfred.Names.Server

  def alive? do
    if GenServer.whereis(@server), do: true, else: false
  end

  def all_known, do: {:all_known} |> call()

  def delete(name), do: {:delete, name} |> call()

  def exists?(name) do
    if lookup(name) |> is_nil(), do: false, else: true
  end

  def lookup(name), do: {:lookup, name} |> call()

  def just_saw(%JustSaw{} = js), do: {:just_saw, js} |> call()
  def just_saw_cast(%JustSaw{} = js), do: {:just_saw, js} |> cast()

  defp call(msg) do
    if alive?(), do: GenServer.call(@server, msg), else: {:no_server, @server}
  end

  defp cast(msg) do
    if alive?(), do: GenServer.cast(@server, msg), else: {:no_server, @server}
  end
end
