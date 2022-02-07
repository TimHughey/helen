defmodule Sally.DatapointAid do
  @moduledoc """
  Supporting functionality for creating Sally.Datapoint for testing
  """

  def avg_daps(%{dap_history: daps} = _ctx, count), do: avg_daps(daps, count)

  def avg_daps([_ | _] = daps, count) do
    daps
    |> Enum.reverse()
    |> Enum.take(count)
    |> Enum.reduce(%{temp_c: 0, temp_f: 0, relhum: 0}, fn dap, acc ->
      Enum.reduce(dap, acc, fn {key, val}, acc ->
        sum = Map.get(acc, key)

        Map.put(acc, key, sum + val)
      end)
    end)
    |> Enum.into(%{}, fn {key, sum} -> {key, sum / count} end)
  end

  def dispatch(%{category: category}, opts_map) do
    unless is_map_key(opts_map, :device), do: raise(":device is missing")

    %{device: %{ident: device_ident}, opts: opts} = opts_map

    status = opts[:status] || "ok"
    data = random_dap(category)

    [filter_extra: [device_ident, status], data: data]
  end

  def historical(%Sally.DevAlias{name: name} = dev_alias, opts_map) do
    %{history: count} = opts_map
    daps = Enum.map(1..count, fn _ -> random_dap() end)
    ref_dt = Timex.now()

    String.to_atom(name) |> Process.put(ref_dt)

    (count - 1)..0
    |> Enum.zip_with(daps, fn num, dap -> {shift(name, num, opts_map), dap} end)
    |> Enum.each(fn {reading_at, data} -> Sally.Datapoint.add(dev_alias, data, reading_at) end)

    #   Ecto.Multi.new()
    #   |> Ecto.Multi.put(:aliases, [dev_alias])
    #   |> Ecto.Multi.run(:datapoint, Sally.DevAlias, :add_datapoint, [data, reading_at])
    #   |> Sally.Repo.transaction()
    #   |> detuple_txn_result()
    # end)

    # NOTE: return the created datapoints
    daps
  end

  def random_dap do
    relhum = random_float(40, 30)
    temp_c = random_float(19, 4)
    temp_f = temp_c * 9 / 5 + 32

    %{temp_c: temp_c, temp_f: Float.round(temp_f, 2), relhum: relhum}
  end

  def random_dap(category) do
    read_us = :rand.uniform(3000) + 1000

    random_dap()
    |> Map.put(:metrics, %{read: read_us})
    |> random_dap_finalize(category)
  end

  def random_dap_finalize(data, category) do
    if(category == "celsius", do: Map.drop(data, [:relhum]), else: data)
  end

  def random_float(low, range) do
    whole = :rand.uniform(range) + low
    decimal = :rand.uniform(99)
    decimal = if(decimal == 0, do: decimal, else: decimal / 100)

    whole + decimal
  end

  @shifts [:hours, :minutes, :seconds, :milliseconds]
  @shift_default [minutes: -1]
  def shift(name, num, opts_map) do
    name_atom = String.to_atom(name)
    ref_dt = Process.get(name_atom)
    shift_opts = shift_opts(num, opts_map)

    Timex.shift(ref_dt, shift_opts)
  end

  def shift_opts(num, opts_map) do
    case Map.take(opts_map, @shifts) do
      x when is_map(x) and map_size(x) == 0 -> @shift_default
      shifts -> shifts |> Enum.into([])
    end
    |> Enum.map(fn {key, val} -> {key, num * val} end)
  end
end
