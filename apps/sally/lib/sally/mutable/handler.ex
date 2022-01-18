defmodule Sally.Mutable.Handler do
  require Logger
  require Ecto.Query

  use Sally.Message.Handler, restart: :permanent, shutdown: 1000

  @spec db_actions(Sally.Dispatch.t()) :: {:ok, map()} | {:error, map()}
  def db_actions(%Sally.Dispatch{} = msg) do
    Ecto.Multi.new()
    |> Ecto.Multi.put(:data, msg.data)
    |> Ecto.Multi.put(:seen_at, msg.sent_at)
    |> Ecto.Multi.insert(:device, Sally.Device.changeset(msg, msg.host), Sally.Device.insert_opts())
    |> Ecto.Multi.run(:aliases, Sally.DevAlias, :load_aliases, [])
    |> Ecto.Multi.merge(Sally.DevAlias, :align_status, [])
    |> Ecto.Multi.update_all(:just_saw_db, fn x -> Sally.DevAlias.just_saw_db(x) end, [])
    |> Sally.Repo.transaction()
  end

  def db_cmd_ack(%Sally.Dispatch{} = msg, cmd) do
    Ecto.Multi.new()
    |> Ecto.Multi.put(:cmd_to_ack, cmd)
    |> Ecto.Multi.put(:seen_at, msg.sent_at)
    |> Ecto.Multi.put(:sent_at, msg.sent_at)
    |> Ecto.Multi.put(:recv_at, msg.recv_at)
    |> Ecto.Multi.update(:command, fn x -> Sally.Command.ack_now_cs(x, :ack) end, returning: true)
    |> Ecto.Multi.update(:aliases, fn x -> Sally.DevAlias.mark_updated(x, :command) end, returning: true)
    |> Ecto.Multi.update(:device, fn x -> device_last_seen_cs(x) end, returning: true)
    |> Sally.Repo.transaction()
  end

  @impl true
  def process(%Sally.Dispatch{category: "status", filter_extra: [_ident, "ok"]} = msg) do
    Logger.debug("BEFORE PROCESSING\n#{inspect(msg, pretty: true)}")

    case db_actions(msg) do
      {:ok, txn} ->
        # HACK: get the updated DevAlias for just_saw/2
        dev_aliases = Enum.map(txn.aliases, fn %{name: name} -> Sally.Command.status(name, []) end)

        :ok = Sally.DevAlias.just_saw(dev_aliases, seen_at: msg.sent_at)

        Sally.Dispatch.valid(msg, txn)

      {:error, error} ->
        Sally.Dispatch.invalid(msg, error)
    end
  end

  # the ident encountered an error
  @impl true
  def process(%Sally.Dispatch{category: "status", filter_extra: [ident, "error"]} = msg) do
    Betty.app_error(__MODULE__, ident: ident, mutable: true, hostname: msg.host.name)

    msg
  end

  @impl true
  def process(%Sally.Dispatch{category: "cmdack", filter_extra: [refid | _]} = msg) do
    cmd = Sally.Command.tracked_info(refid)

    case db_cmd_ack(msg, cmd) do
      {:ok, txn} ->
        :ok = Sally.Command.release(refid, [])

        # HACK: assemble an appropriate DevAlias for DevAlias.just_saw/2 to properly detect it's nature
        dev_alias = struct(txn.aliases, cmds: txn.command)

        :ok = Sally.DevAlias.just_saw(dev_alias, seen_at: msg.sent_at)

        Sally.Dispatch.valid(msg, txn)

      {:error, error} ->
        Sally.Dispatch.invalid(msg, error)
    end
  end

  ##
  ## Private
  ##

  defp device_last_seen_cs(multi_changes) do
    %{aliases: aliases, seen_at: at} = multi_changes

    Sally.DevAlias.device_id(aliases)
    |> Sally.Device.seen_at_cs(at)
  end
end
