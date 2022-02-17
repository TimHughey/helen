defmodule Betty.Metric do
  @moduledoc false

  defstruct measurement: nil, fields: %{}, tags: %{}, timestamp: nil

  @type t :: %__MODULE__{
          measurement: String.t(),
          fields: map(),
          tags: map(),
          timestamp: nil | pos_integer()
        }

  def new(fields) when is_list(fields), do: struct(__MODULE__, fields)

  def new(measurement, fields, tags) do
    [measurement: measurement, fields: fields, tags: tags]
    |> new()
  end

  @doc """
  Finalize and write the Metric to `Instream`

  """
  def write(%__MODULE__{} = m) do
    # rationalize field and tag values into maps
    fields = map_fields(m.fields)
    tags = map_tags(m.tags)

    # ensure timestamp
    tstamp = m.timestamp || System.os_time(:nanosecond)

    # opts for instream
    instream_opts = [precision: :nanosecond, async: true]

    # assemble the final Metric
    final_metric = struct(m, fields: fields, tags: tags, timestamp: tstamp)

    # return the result of writing the points and the final metrics map as tuple
    rc = to_points(final_metric) |> Betty.Connection.write(instream_opts)

    {rc, final_metric}
  end

  # NOTE: fields must always be a numeric value
  defp map_fields(x) when is_struct(x), do: Map.from_struct(x)

  defp map_fields(kv_list) do
    Enum.map(kv_list, fn
      {k, v} when is_boolean(v) -> {k, if(v, do: 1, else: -1)}
      {k, v} when is_float(v) -> {k, Float.round(v, 3)}
      kv -> kv
    end)
    |> Enum.filter(&match?({_, v} when is_number(v), &1))

    #
    # for kv <- kv_list do
    #   case kv do
    #     {k, true} -> {k, 1}
    #     {k, false} -> {k, -1}
    #     {k, v} when is_float(v) -> {k, Float.round(v, 3)}
    #     kv -> kv
    #   end
    # end
    # |> Enum.filter(fn {_, v} -> is_number(v) end)
  end

  # NOTE: tags can be a mix of numbers and strings
  defp map_tags(x) when is_struct(x), do: Map.from_struct(x)

  @make_mod [:module, :server_name]
  defp map_tags(kv_list) do
    Enum.map(kv_list, fn
      {k, mod} when k in @make_mod and is_atom(mod) -> {k, mod_to_string(mod)}
      {k, v} when is_atom(v) -> {k, to_string(v)}
      kv -> kv
    end)
    |> Enum.reject(&match?({_, nil}, &1))
  end

  # remove Elixir from module names
  defp mod_to_string(mod) do
    case mod do
      nil -> nil
      mod when is_atom(mod) -> Module.split(mod) |> Enum.join(".")
      mod -> mod
    end
  end

  defp to_points(%__MODULE__{} = m) do
    %{points: m |> Map.from_struct() |> List.wrap()}
  end
end
