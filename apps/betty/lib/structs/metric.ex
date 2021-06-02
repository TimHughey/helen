defmodule Betty.Metric do
  defstruct measurement: nil, fields: %{}, tags: %{}, timestamp: nil

  alias Betty.Metric

  def into_map(%Metric{} = mm) do
    %Metric{
      mm
      | fields: map_values(mm.fields),
        tags: map_values(mm.tags),
        timestamp: mm.timestamp || System.os_time(:nanosecond)
    }
    |> Map.from_struct()
  end

  # (1 of 2) convert structs to maps, then map values
  defp map_values(field_or_tag_struct) when is_struct(field_or_tag_struct) do
    Map.from_struct(field_or_tag_struct) |> map_values
  end

  # (2 of 2) received a map, good to go
  defp map_values(field_or_tag_map) when is_map(field_or_tag_map) do
    for field_or_tag <- field_or_tag_map, into: %{} do
      case field_or_tag do
        {k, true} -> {k, 1}
        {k, false} -> {k, 0}
        {k, mod} when k in [:mod, :module] and is_atom(mod) -> {k, mod_to_string(mod)}
        {k, val} when is_atom(val) -> {k, to_string(val)}
        {k, val} when is_float(val) -> {k, Float.round(val, 3)}
        kv -> kv
      end
    end
  end

  # remove Elixir. from module names
  defp mod_to_string(mod), do: Module.split(mod) |> Enum.join(".")
end
