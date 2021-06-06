defmodule Sally.Host.Handler do
  require Logger

  use Sally.MsgIn.Handler, restart: :permanent, shutdown: 1000

  alias Broom.TrackerEntry
  alias Sally.{Device, Host}

  @impl true
  def handle_message(%MsgIn{valid?: true} = mi) do
    Logger.debug("\n#{inspect(mi, pretty: true)}")

    case mi do
      %MsgIn{adjunct: "cmdack"} -> cmdack(mi)
      %MsgIn{category: "core", adjunct: "boot"} -> boot(mi)
      %MsgIn{category: x} when x in ["core", "ds", "i2c", "pwm"] -> reading(mi)
      %MsgIn{category: "boot"} -> boot(mi)
    end
    |> Sally.Repo.transaction()
    |> post_process()
  end

  defp boot(%MsgIn{} = mi) do
    mi |> start_multi_and_update_host()
  end

  defp cmdack(%MsgIn{} = mi) do
    mi |> start_multi_and_update_host()
  end

  defp post_process({:ok, results}) do
    results
  end

  defp post_process(error), do: error

  defp reading(%MsgIn{} = mi) do
    start_multi_and_update_host(mi)
    |> Ecto.Multi.insert(:device, fn %{host: h} -> Device.changeset(mi, h) end, Device.insert_opts())
  end

  defp start_multi_and_update_host(%MsgIn{} = mi) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:msg_in, fn _repo, _changes -> {:ok, mi} end)
    |> Ecto.Multi.insert(:host, Host.changeset(mi), Host.insert_opts())
  end

  # defp cmdack(%MsgIn{} = mi) do
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
  #       %MsgInFlight{ident: ident, release: te, metric_rc: metric_rc} |> MsgInFlight.just_saw([dev_alias])
  #
  #     error ->
  #       # TODO properly fill out this error
  #       %MsgInFlight{faults: [cmdack: error]}
  #   end
  # end
  #
  # defp apply_reported_data(dev_aliases, data) do
  #   for %DB.Alias{pio: pio} = da <- dev_aliases, {^pio, cmd} <- data do
  #     DB.Alias.update_cmd(da, cmd)
  #   end
  # end
  #
  # defp report(%MsgIn{} = mi) do
  #   device = update_device(mi)
  #   dev_aliases = DB.Device.get_aliases(device)
  #   applied_data = apply_reported_data(dev_aliases, mi.data)
  #   metrics = write_applied_data_metrics(applied_data, mi.data, mi.sent_at)
  #
  #   %MsgInFlight{ident: device, applied_data: applied_data, metrics: metrics}
  #   |> MsgInFlight.just_saw(applied_data)
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
  # defp update_device(%MsgIn{} = mi) do
  #   %{
  #     ident: mi.ident,
  #     host: mi.host,
  #     pios: mi.data[:pios],
  #     last_seen_at: mi.recv_at
  #   }
  #   |> DB.Device.upsert()
  # end
end
