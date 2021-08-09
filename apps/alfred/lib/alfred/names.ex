defmodule Alfred.Names do
  @moduledoc """
  Alfred Names Public API
  """

  alias Alfred.JustSaw
  alias Alfred.KnownName

  @server Alfred.Names.Server

  def all_known, do: {:all_known} |> call()

  def delete(name), do: {:delete, name} |> call()

  def exists?(name) do
    if lookup(name) |> KnownName.unknown?(), do: false, else: true
  end

  def lookup(name), do: {:lookup, name} |> call()

  def just_saw(%JustSaw{} = js), do: {:just_saw, js} |> call()
  def just_saw_cast(%JustSaw{} = js), do: {:just_saw, js} |> cast()

  defp call(msg) do
    GenServer.call(@server, msg)
  rescue
    _ -> {:no_server, @server}
  end

  defp cast(msg) do
    GenServer.cast(@server, msg)
  rescue
    _ -> {:no_server, @server}
  end
end
