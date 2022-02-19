defmodule Betty.Metric do
  @moduledoc false

  @doc """
  Finalize and write the Metric to `Instream`

  """

  @base [:measurement]
  @instream_opts [precision: :nanosecond, async: true]
  @map_keys [:fields, :tags]
  @steps [:fields, :tags, :timestamp, :write, :finalize]
  @write_keys [:measurement, :fields, :tags, :timestamp]
  @doc since: "0.4.0"
  def write([_ | _] = opts), do: Enum.into(opts, %{}) |> write()

  def write(%{} = opts_map) do
    base = Map.take(opts_map, @base)

    unless map_size(base) > 0, do: raise("measurement missing: #{inspect(opts_map, pretty: true)}")

    Enum.reduce(@steps, base, fn
      key, acc when key in @map_keys and is_map_key(opts_map, key) -> map(acc, key, opts_map)
      :timestamp, acc -> timestamp(acc, opts_map)
      :write, acc -> write_point(acc, @instream_opts)
      :finalize, %{write: write} = acc -> {write, Map.drop(acc, [:write])}
      key, _acc -> raise("missing opt or step: #{inspect(key)}")
    end)
  end

  @make_mod [:module, :server_name]
  def map(acc, key, opts_map) do
    data = Map.get(opts_map, key)

    unless Enum.count(data) > 0, do: raise("#{inspect(key)} is empty")

    case key do
      :fields ->
        # NOTE: fields must always be an numeric value
        Enum.map(data, fn
          {k, v} when is_boolean(v) -> {k, if(v, do: 1, else: -1)}
          {k, v} when is_float(v) -> {k, Float.round(v, 3)}
          {k, v} when is_integer(v) -> {k, v}
          {k, _v} -> {k, nil}
        end)

      :tags ->
        Enum.map(data, fn
          {k, mod} when k in @make_mod and is_atom(mod) -> {k, inspect(mod)}
          {k, v} when is_atom(v) -> {k, to_string(v)}
          {k, <<_::binary>> = v} -> {k, v}
          {k, _} -> {k, nil}
        end)
    end
    |> Enum.reject(&match?({_, x} when is_nil(x) or x == "", &1))
    |> Enum.into(%{})
    |> then(fn clean -> put_in(acc, [key], clean) end)
  end

  def timestamp(acc, opts_map) do
    ts = Map.get(opts_map, :timestamp, System.os_time(:nanosecond))
    put_in(acc, [:timestamp], ts)
  end

  def write_point(%{} = acc, opts) do
    point = Map.take(acc, @write_keys)
    rc = Betty.Connection.write(%{points: [point]}, opts)

    put_in(acc, [:write], rc)
  end
end
