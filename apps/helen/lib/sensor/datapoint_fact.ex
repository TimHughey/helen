defmodule Sensor.DataPoint.Fact do
  alias Sensor.DB.{Alias, DataPoint, Device}

  def write_metric(%{datapoint_rc: {:ok, datapoint}, device: {:ok, device}} = msg) do
    metric = assemble_metric(device, datapoint, msg.msg_recv_dt)
    rc = Fact.Influx.write(metric, precision: :nanosecond, async: true)

    put_in(msg, [:metric_rc], {rc, metric})
  end

  def write_metric(msg), do: put_in(msg, [:metric_rc], {:ok, :no_metric_match})

  defp as_fahrenheit(temp_c), do: temp_c * 1.8 + 32.0

  defp assemble_metric(device, datapoint, recv_dt) do
    %{
      points: [
        %{
          measurement: "sensor",
          fields: fields(datapoint),
          tags: tags(device, datapoint),
          timestamp: DateTime.to_unix(recv_dt, :nanosecond)
        }
      ]
    }
  end

  # (1 of 2) this datapoint has temperature and humidity
  defp fields(%DataPoint{temp_c: tc, relhum: rh}) do
    %{temp_c: tc, temp_f: as_fahrenheit(tc), relhum: rh}
  end

  # (1 of 2) this datapoint only has temperature
  defp fields(%DataPoint{temp_c: tc}) do
    %{temp_c: tc, temp_f: as_fahrenheit(tc)}
  end

  defp tags(%Device{device: d, host: h}, %DataPoint{alias: %Alias{name: n}}) do
    %{device: d, host: h, name: n}
  end
end
