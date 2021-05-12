defmodule Alfred.Notify do
  @moduledoc """
  Alfred Notify Public API
  """

  alias Alfred.NamesAgent

  @server Alfred.NotifyServer

  def alive? do
    if GenServer.whereis(@server), do: true, else: false
  end

  def names_registered, do: {:names_registered} |> call()

  def notify(seen_list) when is_list(seen_list) do
    {:seen_list, seen_list} |> cast()
  end

  def register(name, opts \\ []) do
    opts = Keyword.put_new(opts, :link, true)
    make_opts = fn ms -> [interval_ms: ms, link: opts[:link]] end

    interval = opts[:interval] || opts[:notify_interval] || "PT1M"

    case {NamesAgent.exists?(name), EasyTime.iso8601_duration_to_ms(interval)} do
      {true, x} when is_integer(x) -> {:register, name, make_opts.(x)} |> call()
      {false, _} -> {:failed, "unknown name: #{name}"}
      {_, {:failed, msg}} -> {:failed, "invalid interval: #{inspect(interval)}, #{msg}"}
    end
  end

  defp call(msg) do
    if alive?(), do: GenServer.call(@server, msg), else: {:no_server, @server}
  end

  defp cast(msg) do
    if alive?(), do: GenServer.cast(@server, msg), else: {:no_server, @server}
  end
end
