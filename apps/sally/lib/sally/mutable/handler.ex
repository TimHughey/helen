defmodule Sally.Mutable.Handler do
  @moduledoc false

  require Logger
  require Ecto.Query

  use Sally.Message.Handler, restart: :permanent, shutdown: 1000

  @impl true
  # NOTE: filter_extra: [_ident, "error"] are handled upstream
  def process(%Sally.Dispatch{category: "status", filter_extra: [_ident, "ok"]} = msg) do
    device_changes = Sally.Device.changeset(msg, msg.host)
    device_insert_opts = Sally.Device.insert_opts()

    Ecto.Multi.new()
    |> Ecto.Multi.put(:data, msg.data)
    |> Ecto.Multi.put(:seen_at, msg.sent_at)
    |> Ecto.Multi.insert(:device, device_changes, device_insert_opts)
    |> Ecto.Multi.run(:aliases, Sally.DevAlias, :load_aliases, [])
    |> Ecto.Multi.merge(Sally.DevAlias, :align_status, [])
    |> Ecto.Multi.update_all(:just_saw_db, &Sally.DevAlias.just_saw_db(&1), [])
    |> Sally.Repo.transaction()
  end

  @return [returning: true]
  @impl true
  def process(%Sally.Dispatch{category: "cmdack", filter_extra: [refid | _]} = msg) do
    cmd = Sally.Command.tracked_info(refid)

    Ecto.Multi.new()
    |> Ecto.Multi.put(:cmd_to_ack, cmd)
    |> Ecto.Multi.put(:seen_at, msg.sent_at)
    |> Ecto.Multi.put(:sent_at, msg.sent_at)
    |> Ecto.Multi.put(:recv_at, msg.recv_at)
    |> Ecto.Multi.update(:command, &Sally.Command.ack_now_cs(&1, :ack), @return)
    |> Ecto.Multi.update(:aliases, &Sally.DevAlias.mark_updated(&1, :command), @return)
    |> Ecto.Multi.update(:device, &Sally.Device.seen_at_cs(&1), @return)
    |> Sally.Repo.transaction()
  end

  @impl true
  def post_process(%{category: "status", filter_extra: [_ident, "ok"], txn_info: txn}) do
    %{aliases: aliases, device: device, seen_at: seen_at} = txn

    register_opts = Sally.Device.name_registration_opts(device, seen_at: seen_at)
    :ok = Sally.DevAlias.just_saw(aliases, register_opts)
  end

  @impl true
  def post_process(%{category: "cmdack", filter_extra: [refid | _], txn_info: txn}) do
    :ok = Sally.Command.release(refid, [])

    %{aliases: aliases, device: device, seen_at: seen_at} = txn

    register_opts = Sally.Device.name_registration_opts(device, seen_at: seen_at)
    :ok = Sally.DevAlias.just_saw(aliases, register_opts)
  end
end
