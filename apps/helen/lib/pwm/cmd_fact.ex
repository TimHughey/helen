defmodule PulseWidth.Command.Fact do
  use Timex

  alias PulseWidth.DB.{Alias, Command, Device}

  def filter_cmd_field(field) do
    case field do
      # only write orphan when it is true
      {:orphan, true} -> true
      {:orphan, false} -> false
      # don't write any values that are nil
      {_k, v} when is_nil(v) -> false
      # write anything that didn't match above
      {_k, _v} -> true
    end
  end

  def fields(cmd) do
    Map.take(cmd, [:cmd, :rt_latency_us, :acked, :orphan])
    |> Enum.filter(&filter_cmd_field/1)
    |> Enum.into(%{})
  end

  def assemble_metric(device, cmd, recv_dt) do
    %{
      points: [
        %{
          measurement: "switch",
          fields: fields(cmd),
          tags: tags(device, cmd),
          timestamp: DateTime.to_unix(recv_dt, :nanosecond)
        }
      ]
    }
  end

  def tags(%Device{device: d, host: h}, %Command{alias: %Alias{name: n}}) do
    %{device: d, host: h, name: n}
  end

  def write_metric(%{cmd_rc: {:ok, cmd}, device: {:ok, device}, msg_recv_dt: recv_dt} = msg) do
    metric = assemble_metric(device, cmd, recv_dt)
    rc = Fact.Influx.write(metric, precision: :nanosecond, async: true)

    put_in(msg, [:metric_rc], {rc, metric})
  end

  def write_metric(msg), do: put_in(msg, [:metric_rc], {:ok, :no_metric_match})
end
