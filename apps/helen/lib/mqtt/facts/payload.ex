defmodule Mqtt.Client.Fact.Payload do
  @moduledoc """
  Timeseries metrics for Mqtt Client Payloads
  """
  use Timex

  def write_specific_metric({:publish, feed, payload, _pub_opts}) do
    import Fact.Influx, only: [write: 2]
    import Helen.Time.Helper, only: [unix_now: 1]
    import IO, only: [iodata_length: 1]

    [_env, host, subtopic, _mtime] = String.split(feed, "/")

    {:processed,
     %{
       points: [
         %{
           measurement: "mqtt",
           fields: %{payload_bytes: iodata_length(payload)},
           tags: %{host: host, subtopic: subtopic, tx_or_rx: "tx"},
           timestamp: unix_now(:nanosecond)
         }
       ]
     }
     |> write(precision: :nanosecond, async: true)}
  end

  def write_specific_metric(%{payload: payload, host: src_host}) do
    import Fact.Influx, only: [write: 2]
    import Helen.Time.Helper, only: [unix_now: 1]
    import IO, only: [iodata_length: 1]

    {:processed,
     %{
       points: [
         %{
           measurement: "mqtt",
           fields: %{payload_bytes: iodata_length(payload)},
           tags: %{tx_or_rx: "rx", host: src_host},
           timestamp: unix_now(:nanosecond)
         }
       ]
     }
     |> write(precision: :nanosecond, async: true)}
  end

  def write_specific_metric(_mqtt_payload) do
    {:processed, :no_match}
  end
end
