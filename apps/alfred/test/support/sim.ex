defmodule AlfredSim do
  def parse_name(name) do
    re = ~r/^(?<type>\w+)\s([\w\d_]+)\s(?<rc>[\w\d_]+)\s(?<data>[\w\d._\s]+)$/

    captures = Regex.named_captures(re, name)

    for {k, v} <- captures, into: %{}, do: {String.to_atom(k), v}
  end
end
