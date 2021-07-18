defmodule Betty.Metric do
  alias __MODULE__

  defstruct measurement: nil, fields: %{}, tags: %{}, timestamp: nil

  @type t :: %Metric{
          measurement: String.t(),
          fields: map(),
          tags: map(),
          timestamp: nil | pos_integer()
        }

  def into_map(%Metric{} = mm) do
    %Metric{
      mm
      | fields: map_values(mm.fields),
        tags: map_values(mm.tags),
        timestamp: mm.timestamp || System.os_time(:nanosecond)
    }
    |> Map.from_struct()
  end

  def new(measurement, fields, tags) do
    %Metric{measurement: measurement, fields: Enum.into(fields, %{}), tags: Enum.into(tags, %{})}
  end

  def write(%Metric{} = m) do
    alias Betty.Connection

    metric = %Metric{
      m
      | fields: map_fields(m.fields),
        tags: map_tags(m.tags),
        timestamp: m.timestamp || System.os_time(:nanosecond)
    }

    # instream supports multiple points per write so wrap this single metric in a list
    points_map = %{points: metric |> Map.from_struct() |> List.wrap()}
    instream_opts = [precision: :nanosecond, async: true]

    # now write the point to the timeseries database
    {Connection.write(points_map, instream_opts), points_map}
  end

  # tags or fields common mappings
  defp map_common(field_or_tag) do
    case field_or_tag do
      {key, mod} when key in [:mod, :module] and is_atom(mod) -> {key, mod_to_string(mod)}
      {key, val} when is_atom(val) -> {key, to_string(val)}
      {key, val} when is_float(val) -> {key, Float.round(val, 3)}
      {key, val} -> {key, val}
    end
  end

  # field mappings
  defp map_fields(fields) do
    for {key, value} <- fields, into: %{} do
      case {key, value} do
        {key, true} -> {key, 1}
        {key, false} -> {key, 0}
        {key, "on"} when key == :cmd -> {key, 1}
        {key, "off"} when key == :cmd -> {key, -1}
        key_val -> map_common(key_val)
      end
    end
  end

  # tag mappings
  defp map_tags(tags) do
    for {key, value} <- tags, into: %{} do
      case {key, value} do
        {key, true} -> {key, "true"}
        {key, false} -> {key, "false"}
        key_val -> map_common(key_val)
      end
    end
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
        {k, false} -> {k, -1}
        {k, mod} when k in [:mod, :module] and is_atom(mod) -> {k, mod_to_string(mod)}
        {k, val} when is_atom(val) -> {k, to_string(val)}
        {k, val} when is_float(val) -> {k, Float.round(val, 3)}
        kv -> kv
      end
    end
  end

  # remove Elixir from module names
  defp mod_to_string(mod), do: Module.split(mod) |> Enum.join(".")
end
