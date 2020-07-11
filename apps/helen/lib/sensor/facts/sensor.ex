defmodule Sensor.Fact do
  @moduledoc """
    Specific processing for Sensor messages
  """

  alias Sensor.DB.{Alias, DataPoint, Device}

  # handle temperature metrics

  # this function will always return a tuple:
  #  a. {:processed, :ok} -- metric was written
  #  b. {:processed, :no_sensor_alias} -- metric not written
  #  c. {:processed, :no_match} -- metric not written, error condition
  def write_specific_metric(
        %DataPoint{} = dp,
        %{
          write_rc: nil,
          device:
            {:ok, %Device{device: d, host: h, _alias_: %Alias{name: n}}},
          msg_recv_dt: recv_dt
        } = _msg
      ) do
    import Fact.Influx, only: [write: 2]

    # assemble the metric fields
    fields =
      Map.take(dp, [:temp_f, :temp_c, :relhum, :moisture])
      |> Enum.reject(fn
        {_k, v} when is_nil(v) -> true
        {_k, _v} -> false
      end)
      |> Enum.into(%{})

    {:processed,
     %{
       points: [
         %{
           measurement: "sensor",
           fields: fields,
           tags: %{device: d, host: h, name: n},
           timestamp: DateTime.to_unix(recv_dt, :nanosecond)
         }
       ]
     }
     |> write(precision: :nanosecond, async: true)}
  end

  def write_specific_metric(
        %DataPoint{},
        %{
          write_rc: nil,
          device: {:ok, %Device{_alias_: sa}}
        } = _msg
      )
      when is_nil(sa) do
    {:processed, :no_sensor_alias}
  end

  def write_specific_metric(_datapoint, _msg) do
    {:processed, :no_match}
  end
end
