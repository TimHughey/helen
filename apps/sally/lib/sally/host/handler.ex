defmodule Sally.Host.Handler do
  require Logger

  use Sally.Message.Handler, restart: :permanent, shutdown: 1000

  alias Sally.Host
  alias Sally.Host.Message, as: Msg
  alias Sally.Host.Reply

  @impl true
  def finalize(%Msg{} = msg) do
    log = fn x ->
      Logger.debug("\n#{inspect(x, pretty: true)}")
      x
    end

    %Msg{msg | final_at: DateTime.utc_now()} |> log.()
  end

  @impl true
  def process(%Msg{} = msg) do
    Logger.debug("BEFORE PROCESSING\n#{inspect(msg, pretty: true)}")

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:host, Host.changeset(msg), Host.insert_opts())
    |> Sally.Repo.transaction()
    |> check_result(msg)
    |> post_process()
    |> finalize()
  end

  @impl true
  def post_process(%Msg{valid?: false} = msg), do: msg

  @impl true
  def post_process(%Msg{category: "boot"} = msg) do
    %Reply{
      ident: msg.ident,
      name: msg.host.name,
      data: Host.boot_payload_data(msg.host),
      filter: "profile"
    }
    |> Reply.send()
    |> Msg.add_reply(msg)
  end

  @impl true
  def post_process(%Msg{category: "log"} = msg) do
    msg
  end

  @impl true
  def post_process(%Msg{category: "ota"} = msg) do
    msg
  end

  @impl true
  def post_process(%Msg{category: "run"} = msg) do
    msg
  end

  defp check_result(txn_result, %Msg{} = msg) do
    case txn_result do
      {:ok, results} -> %Msg{msg | host: results.host}
      {:error, e} -> Msg.invalid(msg, e)
    end
  end

  # defp cmdack(%Msg{} = mi) do
  #   ## cmd acks are straight forward and require only the refid and the message recv at
  #   case Execute.ack_now(mi.data.refid, mi.recv_at) do
  #     {:ok, %TrackerEntry{} = te} ->
  #       dev_alias = Repo.get!(DB.Alias, te.alias_id)
  #       ident = DB.Device.update_last_seen_at(dev_alias.device_id, mi.recv_at)
  #
  #       metric = %Betty.Metric{
  #         measurement: "command",
  #         tags: %{module: __MODULE__, name: dev_alias.name, cmd: te.cmd},
  #         fields: %{
  #           cmd_roundtrip_us: DateTime.diff(te.acked_at, te.sent_at, :microsecond),
  #           cmd_total_us: DateTime.diff(te.released_at, te.sent_at, :microsecond),
  #           release_us: DateTime.diff(te.released_at, mi.recv_at, :microsecond)
  #         }
  #       }
  #
  #       metric_rc = Betty.write_metric(metric)
  #
  #       %MsgFlight{ident: ident, release: te, metric_rc: metric_rc} |> MsgFlight.just_saw([dev_alias])
  #
  #     error ->
  #       # TODO properly fill out this error
  #       %MsgFlight{faults: [cmdack: error]}
  #   end
  # end
  #
  # defp apply_reported_data(dev_aliases, data) do
  #   for %DB.Alias{pio: pio} = da <- dev_aliases, {^pio, cmd} <- data do
  #     DB.Alias.update_cmd(da, cmd)
  #   end
  # end
  #
  # defp report(%Msg{} = mi) do
  #   device = update_device(mi)
  #   dev_aliases = DB.Device.get_aliases(device)
  #   applied_data = apply_reported_data(dev_aliases, mi.data)
  #   metrics = write_applied_data_metrics(applied_data, mi.data, mi.sent_at)
  #
  #   %MsgFlight{ident: device, applied_data: applied_data, metrics: metrics}
  #   |> MsgFlight.just_saw(applied_data)
  # end
  #
  # defp write_applied_data_metrics(applied_data, original_data, sent_at) do
  #   for %DB.Alias{} = dev_alias <- applied_data do
  #     %Betty.Metric{
  #       measurement: "mutables",
  #       tags: %{module: __MODULE__, name: dev_alias.name, cmd: dev_alias.cmd},
  #       fields: %{read_us: original_data[:read_us] || 0},
  #       # each measurement must be at a unique timestamp
  #       timestamp: DateTime.to_unix(sent_at, :nanosecond) + dev_alias.pio
  #     }
  #     |> Betty.write_metric()
  #     |> elem(1)
  #   end
  # end
  #
  # defp update_device(%Msg{} = mi) do
  #   %{
  #     ident: mi.ident,
  #     host: mi.host,
  #     pios: mi.data[:pios],
  #     last_seen_at: mi.recv_at
  #   }
  #   |> DB.Device.upsert()
  # end
end
