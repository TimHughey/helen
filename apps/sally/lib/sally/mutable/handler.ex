defmodule Sally.Mutable.Handler do
  @moduledoc false

  require Logger
  require Ecto.Query

  use Sally.Message.Handler, restart: :permanent, shutdown: 1000

  @type db_actions() :: {:ok, map()} | {:error, map()}

  # the ident encountered an error
  @impl true
  def process(%Sally.Dispatch{category: "status", filter_extra: [ident, "error"]} = msg) do
    Betty.app_error(__MODULE__, ident: ident, mutable: true, hostname: msg.host.name)

    msg
  end

  @impl true
  def process(%Sally.Dispatch{category: "status", filter_extra: [_ident, "ok"]} = msg) do
    Ecto.Multi.new()
    |> Ecto.Multi.put(:data, msg.data)
    |> Ecto.Multi.put(:seen_at, msg.sent_at)
    |> Ecto.Multi.insert(:device, Sally.Device.changeset(msg, msg.host), Sally.Device.insert_opts())
    |> Ecto.Multi.run(:aliases, Sally.DevAlias, :load_aliases, [])
    |> Ecto.Multi.merge(Sally.DevAlias, :align_status, [])
    |> Ecto.Multi.update_all(:just_saw_db, fn x -> Sally.DevAlias.just_saw_db(x) end, [])
    |> Sally.Repo.transaction()
    |> Sally.Dispatch.save_txn_info(msg)
  end

  @impl true
  def process(%Sally.Dispatch{category: "cmdack", filter_extra: [refid | _]} = msg) do
    cmd = Sally.Command.tracked_info(refid)

    Ecto.Multi.new()
    |> Ecto.Multi.put(:cmd_to_ack, cmd)
    |> Ecto.Multi.put(:seen_at, msg.sent_at)
    |> Ecto.Multi.put(:sent_at, msg.sent_at)
    |> Ecto.Multi.put(:recv_at, msg.recv_at)
    |> Ecto.Multi.update(:command, fn x -> Sally.Command.ack_now_cs(x, :ack) end, returning: true)
    |> Ecto.Multi.update(:aliases, fn x -> Sally.DevAlias.mark_updated(x, :command) end, returning: true)
    |> Ecto.Multi.update(:device, fn x -> device_last_seen_cs(x) end, returning: true)
    |> Sally.Repo.transaction()
    |> Sally.Dispatch.save_txn_info(msg)
  end

  @impl true
  def post_process(%{category: "status", filter_extra: [_ident, "ok"], txn_info: txn} = dispatch) do
    :ok = Sally.DevAlias.just_saw(txn.aliases, register_opts(dispatch))

    Sally.Dispatch.valid(dispatch)
  end

  @impl true
  def post_process(%{category: "cmdack", filter_extra: [refid | _], txn_info: txn} = dispatch) do
    :ok = Sally.Command.release(refid, [])
    :ok = Sally.DevAlias.just_saw(txn.aliases, register_opts(dispatch))

    Sally.Dispatch.valid(dispatch)
  end

  @impl true
  def post_process(dispatch), do: Sally.Dispatch.invalid(dispatch, :not_matched)

  ##
  ## Private
  ##

  def register_opts(%{sent_at: seen_at}), do: [seen_at: seen_at, nature: :cmds]

  defp device_last_seen_cs(multi_changes) do
    %{aliases: aliases, seen_at: at} = multi_changes

    Sally.DevAlias.device_id(aliases)
    |> Sally.Device.seen_at_cs(at)
  end
end
