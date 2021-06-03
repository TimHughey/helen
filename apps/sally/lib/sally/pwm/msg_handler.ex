defmodule Sally.PulseWidth.MsgHandler do
  require Logger

  use Sally.MsgIn.Handler, restart: :permanent, shutdown: 1000

  alias Broom.TrackerEntry
  alias Sally.PulseWidth.DB
  alias Sally.PulseWidth.Execute
  alias SallyRepo, as: Repo

  @impl true
  def handle_message(%MsgIn{valid?: true} = mi) do
    Logger.debug("\n#{inspect(mi, pretty: true)}")

    if mi.valid? == true do
      Repo.transaction(fn ->
        Repo.checkout(fn ->
          case mi do
            %MsgIn{misc: "cmdack"} -> cmdack(mi)
            _ -> report(mi)
          end
        end)
      end)
      |> elem(1)
    else
      %MsgInFlight{}
    end
  end

  defp cmdack(%MsgIn{} = mi) do
    ## cmd acks are straight forward and require only the refid and the message recv at
    case Execute.ack_now(mi.data.refid, mi.recv_at) do
      {:ok, %TrackerEntry{} = te} ->
        dev_alias = Repo.get!(DB.Alias, te.alias_id)
        ident = DB.Device.update_last_seen_at(dev_alias.device_id, mi.recv_at)

        metric = %Betty.Metric{
          measurement: "command",
          tags: %{module: __MODULE__, name: dev_alias.name, cmd: te.cmd},
          fields: %{
            cmd_roundtrip_us: DateTime.diff(te.acked_at, te.sent_at, :microsecond),
            cmd_total_us: DateTime.diff(te.released_at, te.sent_at, :microsecond),
            release_us: DateTime.diff(te.released_at, mi.recv_at, :microsecond)
          }
        }

        metric_rc = Betty.write_metric(metric)

        %MsgInFlight{ident: ident, release: te, metric_rc: metric_rc} |> MsgInFlight.just_saw([dev_alias])

      error ->
        # TODO properly fill out this error
        %MsgInFlight{faults: [cmdack: error]}
    end
  end

  defp apply_reported_data(dev_aliases, data) do
    for %DB.Alias{pio: pio} = da <- dev_aliases, {^pio, cmd} <- data do
      DB.Alias.update_cmd(da, cmd)
    end
  end

  defp report(%MsgIn{} = mi) do
    device = update_device(mi)
    dev_aliases = DB.Device.get_aliases(device)
    applied_data = apply_reported_data(dev_aliases, mi.data)
    metrics = write_applied_data_metrics(applied_data, mi.data, mi.sent_at)

    %MsgInFlight{ident: device, applied_data: applied_data, metrics: metrics}
    |> MsgInFlight.just_saw(applied_data)
  end

  defp write_applied_data_metrics(applied_data, original_data, sent_at) do
    for %DB.Alias{} = dev_alias <- applied_data do
      %Betty.Metric{
        measurement: "mutables",
        tags: %{module: __MODULE__, name: dev_alias.name, cmd: dev_alias.cmd},
        fields: %{read_us: original_data[:us] || 0},
        # each measurement must be at a unique timestamp
        timestamp: DateTime.to_unix(sent_at, :nanosecond) + dev_alias.pio
      }
      |> Betty.write_metric()
      |> elem(1)
    end
  end

  defp update_device(%MsgIn{} = mi) do
    %{
      ident: mi.ident,
      host: mi.host,
      pios: mi.data[:pios],
      latency_us: mi.data[:latency_us],
      last_seen_at: mi.recv_at
    }
    |> DB.Device.upsert()
  end
end
