defmodule PulseWidth.Fact.Command do
  @moduledoc """
  Timeseries metrics for PulseWidth Commands
  """
  use Timex

  alias PulseWidth.DB.Command, as: Command
  alias PulseWidth.DB.Device, as: Device

  def write_specific_metric(
        {:ok, %Command{} = cmd},
        %{
          device: {:ok, %Device{device: d, host: h, _alias_: %_{name: n}}},
          msg_recv_dt: recv_dt
        } = _msg
      ) do
    import Fact.Influx, only: [write: 2]

    # assemble the metric fields
    fields =
      Map.take(cmd, [:rt_latency_us, :acked, :orphan])
      |> Enum.filter(fn
        # only write orphan when it is true
        {:orphan, true} -> true
        {:orphan, false} -> false
        # don't write any values that are nil
        {_k, v} when is_nil(v) -> false
        # write anything that didn't match above
        {_k, _v} -> true
      end)
      |> Enum.into(%{})

    {:processed,
     %{
       points: [
         %{
           measurement: "pwm",
           fields: fields,
           tags: %{device: d, host: h, name: n, cmd: "yes"},
           timestamp: DateTime.to_unix(recv_dt, :nanosecond)
         }
       ]
     }
     |> write(precision: :nanosecond, async: true)}
  end

  def write_specific_metric(_switch_cmd, _msg) do
    {:processed, :no_match}
  end
end
