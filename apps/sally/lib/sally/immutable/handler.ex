defmodule Sally.Immutable.Handler do
  require Logger
  require Ecto.Query

  use Sally.Message.Handler, restart: :permanent, shutdown: 1000

  @impl true
  # NOTE: filter_extra: [_ident, "error"] are handled upstream
  def process(%{filter_extra: [_ident, "ok"]} = msg) do
    device_changes = Sally.Device.changeset(msg, msg.host)
    device_insert_opts = Sally.Device.insert_opts()
    add_datapoint_opts = [msg.data, msg.sent_at]

    Ecto.Multi.new()
    |> Ecto.Multi.put(:seen_at, msg.sent_at)
    |> Ecto.Multi.insert(:device, device_changes, device_insert_opts)
    |> Ecto.Multi.run(:aliases, Sally.DevAlias, :load_aliases, [])
    |> Ecto.Multi.run(:datapoint, Sally.DevAlias, :add_datapoint, add_datapoint_opts)
    |> Ecto.Multi.update_all(:just_saw_db, &Sally.DevAlias.just_saw_db(&1), [])
    |> Sally.Repo.transaction()
  end

  @impl true
  @want_keys [:aliases, :datapoint, :device]
  # NOTE: the dispatch is guaranteed to be valid
  def post_process(%{txn_info: txn} = dispatch) do
    %{aliases: aliases, device: device, seen_at: seen_at} = txn

    register_opts = Sally.Device.name_registration_opts(device, seen_at: seen_at)
    :ok = Sally.DevAlias.just_saw(aliases, register_opts)

    Map.take(txn, @want_keys)
    |> Map.put(:data, dispatch.data)
    |> Sally.Datapoint.write_metrics()
  end
end
