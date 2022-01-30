defmodule Sally.Mutable.Dispatch do
  @moduledoc false

  require Logger
  require Ecto.Query

  use Sally.Dispatch, subsystem: "mut", process_many: [status: :aliases]

  @impl true
  # NOTE: filter_extra: [_ident, "error"] are handled upstream
  def process(%{category: "status", filter_extra: [ident, "ok"]} = dispatch) do
    device = Sally.Device.create(ident, dispatch.recv_at, dispatch)
    aliases = Sally.DevAlias.load_aliases(device)

    txn_info = %{device: device, aliases: []}

    Enum.reduce(aliases, txn_info, fn dev_alias, acc ->
      align_key = {:aligned, dev_alias.name}
      aligned_cmd = Sally.DevAlias.align_status(dev_alias, dispatch)
      dev_alias = Sally.DevAlias.ttl_reset(dev_alias, dispatch.recv_at)

      acc
      |> Map.put(align_key, aligned_cmd)
      |> Map.put(:aliases, [dev_alias | acc.aliases])
    end)
    # NOTE: all database operations would have raised on failure so
    # wrap results in an ok tuple to signal success
    |> then(fn txn_info -> {:ok, txn_info} end)
  end

  # @return [returning: true]
  @impl true
  def process(%{category: "cmdack", filter_extra: [refid | _]} = dispatch) do
    cmd = Sally.Command.tracked_info(refid)
    :ok = Sally.Command.track(:complete, refid, dispatch.recv_at)

    cmd = Sally.Command.ack_now(cmd)
    dev_alias = Sally.DevAlias.ttl_reset(cmd)
    device = Sally.Device.ttl_reset(dev_alias)

    {:ok, %{command: cmd, aliases: dev_alias, device: device}}
  end

  @impl true
  def post_process(%{category: "status", filter_extra: [_ident, "ok"]} = dispatch) do
    %{aliases: aliases, device: device} = dispatch.txn_info

    register_opts = Sally.Device.name_registration_opts(device, seen_at: dispatch.recv_at)
    :ok = Sally.DevAlias.just_saw(aliases, register_opts)
  end

  @impl true
  def post_process(%{category: "cmdack"} = dispatch) do
    %{filter_extra: [refid | _]} = dispatch
    :ok = Sally.Command.release(refid, [])

    %{aliases: aliases, device: device} = dispatch.txn_info

    register_opts = Sally.Device.name_registration_opts(device, seen_at: dispatch.recv_at)
    :ok = Sally.DevAlias.just_saw(aliases, register_opts)
  end
end
