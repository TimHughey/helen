defmodule Sensor.DataPoint.Fact do
  alias Sensor.DB.{Alias, DataPoint, Device}

  # (1 of 2) nominal case, there's a list of datapoints to make metrics for
  def write_metric(%{datapoints_rc: {:ok, results}, device: {:ok, device}} = msg) when is_list(results) do
    msg_out = put_in(msg, [:metric_rc], {:ok, []})

    for %{datapoint: datapoint, schema: %Alias{} = schema} <- results, reduce: msg_out do
      %{metric_rc: {_, acc}} = msg_out ->
        metric = assemble_metric(device, schema.name, datapoint, msg.msg_recv_dt)
        rc = Fact.Influx.write(metric, precision: :nanosecond, async: true)

        points = get_in(metric, [:points])
        metrics = [points, acc] |> List.flatten()

        %{msg_out | metric_rc: {rc, metrics}}
    end
  end

  # (2 of 2) no match
  def write_metric(msg) do
    put_in(msg, [:metric_rc], {:ok, []})
  end

  defp as_fahrenheit(temp_c), do: (temp_c * 1.8 + 32.0) |> Float.round(3)

  defp assemble_metric(device, name, datapoint, recv_dt) do
    %{
      points: [
        %{
          measurement: "sensor",
          fields: fields(datapoint),
          tags: tags(device, name),
          timestamp: DateTime.to_unix(recv_dt, :nanosecond)
        }
      ]
    }
  end

  # (1 of 2) this datapoint has temperature and humidity
  defp fields(%DataPoint{temp_c: tc, relhum: rh}) when is_float(tc) and is_float(rh) do
    %{temp_c: tc, temp_f: as_fahrenheit(tc), relhum: rh}
  end

  # (1 of 2) this datapoint only has temperature
  defp fields(%DataPoint{temp_c: tc}) when is_float(tc) do
    %{temp_c: tc, temp_f: as_fahrenheit(tc)}
  end

  defp tags(%Device{device: d, host: h}, n) do
    %{device: d, host: h, name: n}
  end
end
