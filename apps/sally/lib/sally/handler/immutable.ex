defmodule Sally.Immutable.Dispatch do
  require Logger
  require Ecto.Query

  use Sally.Dispatch, subsystem: "immut"

  def accumulate(what, map) do
    Enum.reduce(what, map, fn {key, val}, acc -> %{acc | key => [val | acc[key]]} end)
  end

  @impl true
  # NOTE: filter_extra: [_ident, "error"] are handled upstream
  def process(%{filter_extra: [ident, "ok"]} = dispatch) do
    device = Sally.Device.create(ident, dispatch.recv_at, dispatch)
    aliases = Sally.DevAlias.load_aliases(device)

    txn_info = %{device: device, aliases: [], datapoints: []}

    Enum.reduce(aliases, txn_info, fn dev_alias, acc ->
      [
        datapoints: Sally.Datapoint.add(dev_alias, dispatch.data, dispatch.recv_at),
        aliases: Sally.DevAlias.ttl_reset(dev_alias, dispatch.recv_at)
      ]
      # NOTE: accumulate the db results
      |> accumulate(acc)
    end)
    # NOTE: all database operations would have raised on failure so
    # wrap results in an ok tuple to signal success
    |> then(fn txn_info -> {:ok, txn_info} end)
  end

  @impl true
  @want_keys [:aliases, :datapoints, :device]
  # NOTE: the dispatch is guaranteed to be valid
  def post_process(%{} = dispatch) do
    _ = Sally.DevAlias.register(dispatch.txn_info.aliases)

    Map.take(dispatch.txn_info, @want_keys)
    |> Map.put(:data, dispatch.data)
    |> Sally.Datapoint.write_metrics()
  end
end
