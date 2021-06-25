defmodule Alfred.Notify do
  @moduledoc """
  Alfred Notify Public API
  """

  @server Alfred.Notify.Server

  def alive? do
    if GenServer.whereis(@server), do: true, else: false
  end

  def names_registered, do: {:names_registered} |> call()

  def notify(seen_list) when is_list(seen_list) do
    {:seen_list, seen_list} |> cast()
  end

  @register_default_opts [interval_ms: 60_000, link: true]
  def register(name, opts \\ []) do
    if Alfred.is_name_known?(name) do
      {:register, name, Keyword.merge(@register_default_opts, opts)} |> call()
    else
      {:failed, "unknown name: #{name}"}
    end
  end

  defp call(msg) do
    if alive?(), do: GenServer.call(@server, msg), else: {:no_server, @server}
  end

  defp cast(msg) do
    if alive?(), do: GenServer.cast(@server, msg), else: {:no_server, @server}
  end
end
