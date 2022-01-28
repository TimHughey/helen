defmodule Sally.Immutable.Dispatch do
  require Logger
  require Ecto.Query

  use Sally.Dispatch, subsystem: "immut"

  @impl true
  # NOTE: filter_extra: [_ident, "error"] are handled upstream
  def process(%{filter_extra: [_ident, "ok"]} = dispatch) do
    device_changes = Sally.Device.changeset(dispatch, dispatch.host)
    device_insert_opts = Sally.Device.insert_opts()

    device = Sally.Repo.insert!(device_changes, device_insert_opts)
    aliases = Sally.DevAlias.load_aliases(device)

    txn_info = %{device: device, aliases: [], datapoints: []}

    Enum.reduce(aliases, txn_info, fn dev_alias, acc ->
      [
        datapoints: Sally.Datapoint.add(dev_alias, dispatch.data, dispatch.recv_at),
        aliases: Sally.DevAlias.ttl_reset(dev_alias, dispatch.recv_at)
      ]
      # NOTE: accumulate the db results
      |> Enum.reduce(acc, fn {key, val}, acc2 -> Map.put(acc2, key, [val | Map.get(acc2, key)]) end)
    end)
    # NOTE: all database operations would have raised on failure so
    # wrap results in an ok tuple to signal success
    |> then(fn txn_info -> {:ok, txn_info} end)

    # Ecto.Multi.new()
    # |> Ecto.Multi.put(:dispatch, dispatch)
    # |> Ecto.Multi.insert(:device, device_changes, device_insert_opts)
    # |> Ecto.Multi.run(:aliases, Sally.DevAlias, :load_aliases, [])
    # |> Ecto.Multi.run(:datapoint, Sally.DevAlias, :add_datapoint, add_datapoint_opts)
    # |> Ecto.Multi.update_all(:just_saw_db, &Sally.DevAlias.just_saw_db(&1), [])
    # |> Sally.Repo.transaction()
  end

  @impl true
  @want_keys [:aliases, :datapoints, :device]
  # NOTE: the dispatch is guaranteed to be valid
  def post_process(%{} = dispatch) do
    %{aliases: aliases, device: device} = dispatch.txn_info

    register_opts = Sally.Device.name_registration_opts(device, seen_at: dispatch.recv_at)
    :ok = Sally.DevAlias.just_saw(aliases, register_opts)

    Map.take(dispatch.txn_info, @want_keys)
    |> Map.put(:data, dispatch.data)
    |> Sally.Datapoint.write_metrics()
  end
end
