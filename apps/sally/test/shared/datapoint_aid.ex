defmodule Sally.DatapointAid do
  @moduledoc """
  Supporting functionality for creating Sally.Datapoint for testing
  """

  def avg_daps(%{dap_history: daps} = _ctx, count), do: avg_daps(daps, count)

  def avg_daps([_ | _] = daps, count) do
    daps
    #  |> Enum.reverse()
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

  @shifts [:hours, :minutes, :seconds, :milliseconds]
  @shift_default [minutes: -1]
  def historical(%Sally.DevAlias{} = dev_alias, opts_map) do
    history = get_in(opts_map, [:_daps_, :history]) || 0

    shift_opts = Map.take(opts_map, @shifts) |> Enum.into([])
    shift_opts = if(shift_opts == [], do: @shift_default, else: shift_opts)

    # NOTE: get ref_dt ONCE because datapoint reading at must shift from a fixed point
    ref_dt = get_in(opts_map, [:ref_dt]) || Timex.now()

    # NOTE: create the daps in reverse order
    Enum.reduce((history - 1)..0, [], fn
      num, daps_acc ->
        # NOTE: create the shifts for _THIS_ datapoint based on num and fixed ref_dt
        shifts = Enum.map(shift_opts, fn {key, val} -> {key, num * val} end)
        reading_at = Timex.shift(ref_dt, shifts)
        dap = random_dap()

        _ = Sally.Datapoint.add(dev_alias, dap, reading_at)

        # NOTE: accumulate the random daps
        [dap | daps_acc]
    end)
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
end
