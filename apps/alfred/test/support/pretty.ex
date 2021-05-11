defmodule AlfredTestPretty do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      import AlfredTestPretty
    end
  end

  def pretty(x) do
    ["\n", inspect(x, pretty: true)] |> IO.iodata_to_binary()
  end

  def pretty(msg, x) do
    [msg, "\n", inspect(x, pretty: true)] |> IO.iodata_to_binary()
  end

  def pretty(msg, should_be, x) when is_binary(msg) and is_binary(should_be) do
    [msg, " ", should_be, "\n", inspect(x, pretty: true)] |> IO.iodata_to_binary()
  end

  def pretty_puts(list) when is_list(list) do
    case list do
      [msg] when is_binary(msg) -> [msg]
      [x] -> ["\n", inspect(x, pretty: true), "\n"]
      [msg, x] when is_binary(msg) -> [msg, "\n", inspect(x, pretty: true)]
    end
    |> IO.puts()
  end

  def pretty_puts(x), do: pretty_puts([x])
  def pretty_puts(x, y), do: pretty_puts([x, y])
end
