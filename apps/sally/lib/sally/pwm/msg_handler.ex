defmodule Sally.PulseWidth.MsgHandler do
  require Logger

  use Sally.MsgIn.Handler, restart: :permanent, shutdown: 1000

  alias Broom.TrackerEntry
  alias Sally.PulseWidth.DB
  alias Sally.PulseWidth.DB.Device
  alias Sally.PulseWidth.Execute
  alias SallyRepo, as: Repo

  @impl true
  def handle_message(%MsgIn{} = mi) do
    Logger.debug("\n#{inspect(mi, pretty: true)}")

    Repo.transaction(fn ->
      Repo.checkout(fn ->
        case mi do
          %MsgIn{misc: "cmdack"} -> cmdack(mi)
          _ -> report(mi)
        end
      end)
    end)
    |> elem(1)
  end

  ##
  ## cmd acks are straight forward and require only the refid and the message recv at

  defp cmdack(%MsgIn{} = mi) do
    case Execute.ack_now(mi.data.refid, mi.recv_at) do
      {:ok, %TrackerEntry{} = te} ->
        dev_alias = Repo.get!(DB.Alias, te.alias_id)
        ident = Device.update_last_seen_at(dev_alias.device_id, mi.recv_at)
        just_saw = Alfred.just_saw([dev_alias])

        metric = %Betty.Metric{
          measurement: "command",
          fields: %{
            cmd_roundtrip_us: DateTime.diff(te.acked_at, te.sent_at, :microsecond),
            cmd_total_us: DateTime.diff(te.released_at, te.sent_at, :microsecond),
            release_us: DateTime.diff(te.released_at, mi.recv_at, :microsecond)
          },
          tags: %{module: __MODULE__, name: dev_alias.name, cmd: te.cmd}
        }

        metric_rc = Betty.write_metric(metric)

        %MsgInFlight{ident: ident, release: te, just_saw: just_saw, metric_rc: metric_rc}

      error ->
        # TODO properly fill out this error
        %MsgInFlight{faults: [cmdack: error]}
    end
  end

  defp report(%MsgIn{} = mi) do
    ident = update_device(mi) |> Device.load_aliases()
    %MsgInFlight{ident: ident}
  end

  defp update_device(%MsgIn{} = mi) do
    %{
      ident: mi.ident,
      host: mi.host,
      pios: mi.data[:pios],
      latency_us: mi.data[:latency_us],
      last_seen_at: mi.recv_at
    }
    |> Device.upsert()
  end
end
