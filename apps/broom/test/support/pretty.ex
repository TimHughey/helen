defmodule BroomTestPretty do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      import BroomTestPretty
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
      [msg, x] when is_binary(msg) -> [msg, "\n", inspect(x, pretty: true)]
      x -> ["\n", inspect(x, pretty: true), "\n"]
    end
    |> IO.puts()
  end

  def pretty_puts(x), do: pretty_puts([x])
  def pretty_puts(x, y), do: pretty_puts([x, y])

  def pretty_puts_passthrough(x) do
    pass = fn {out, x} ->
      IO.puts(out)
      x
    end

    case x do
      x when is_map(x) -> {["\n", inspect(x, pretty: true), "\n"], x} |> pass.()
      x when is_tuple(x) -> {[inspect(x, pretty: true)], x} |> pass.()
      [x | _] = list when is_atom(x) -> {[inspect(list, pretty: true)], list} |> pass.()
    end
  end
end
