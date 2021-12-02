defmodule Sally.Mutable.Handler do
  require Logger
  require Ecto.Query

  use Sally.Message.Handler, restart: :permanent, shutdown: 1000

  alias __MODULE__

  # alias Alfred.MutableStatus, as: MutStatus
  alias Sally.{Command, DevAlias, Device, Execute, Mutable}
  alias Sally.Dispatch
  alias Sally.Repo

  @spec db_actions(Dispatch.t()) :: {:ok, map()} | {:error, map()}
  def db_actions(%Dispatch{} = msg) do
    alias Ecto.Multi
    alias Sally.Repo

    sent_at = msg.sent_at

    Multi.new()
    |> Multi.insert(:device, Device.changeset(msg, msg.host), Device.insert_opts())
    |> Multi.run(:aliases, DevAlias, :load_aliases_with_last_cmd, [])
    |> Multi.merge(Mutable, :align_status_cs, [msg.data, sent_at])
    |> Multi.run(:seen_list, DevAlias, :just_saw, [sent_at])
    |> Repo.transaction()
  end

  def db_cmd_ack(%Dispatch{} = msg, command_id, dev_alias_id) do
    alias Ecto.Multi

    sent_at = msg.sent_at

    command_cs = Command.ack_now_cs(command_id, sent_at, msg.recv_at, :ack)

    Multi.new()
    |> Multi.update(:command, command_cs, returning: true)
    |> Multi.run(:seen_list, DevAlias, :just_saw_id, [dev_alias_id, sent_at])
    |> Multi.update(:device, fn %{seen_list: x} -> device_last_seen_cs(x, sent_at) end, returning: true)
    |> Repo.transaction()
  end

  @impl true
  def process(%Dispatch{category: "status", filter_extra: [_ident, "ok"]} = msg) do
    Logger.debug("BEFORE PROCESSING\n#{inspect(msg, pretty: true)}")

    case db_actions(msg) do
      {:ok, txn_results} ->
        # NOTE: alert Alfred of just seen names after txn is complete

        Sally.just_saw(txn_results.device, txn_results.seen_list)
        |> Dispatch.save_seen_list(msg)
        |> Dispatch.valid(txn_results)

      {:error, error} ->
        Dispatch.invalid(msg, error)
    end
  end

  # the ident encountered an error
  @impl true
  def process(%Dispatch{category: "status", filter_extra: [ident, "error"]} = msg) do
    Betty.app_error(__MODULE__, ident: ident, mutable: true, hostname: msg.host.name)

    msg
  end

  @impl true
  def process(%Dispatch{category: "cmdack", filter_extra: [refid | _]} = msg) do
    # alias Broom.TrackerEntry
    # alias Sally.Repo
    te = Execute.get_tracked(refid)

    case db_cmd_ack(msg, te.schema_id, te.dev_alias_id) do
      {:ok, txn_results} ->
        released_te = Execute.release(txn_results.command)
        write_ack_metrics(txn_results.seen_list, released_te, msg)

        # NOTE: alert Alfred of just seen names after txn is complete
        Sally.just_saw(txn_results.device, txn_results.seen_list)
        |> Dispatch.save_seen_list(msg)
        |> Dispatch.valid(txn_results)

      {:error, error} ->
        Dispatch.invalid(msg, error)
    end
  end

  def write_ack_metrics([%DevAlias{} | _] = seen_list, te, msg) do
    for %DevAlias{} = dev_alias <- seen_list do
      [
        measurement: "command",
        tags: [module: __MODULE__, name: dev_alias.name, cmd: te.cmd],
        fields: [
          cmd_roundtrip_us: DateTime.diff(te.acked_at, te.sent_at, :microsecond),
          cmd_total_us: DateTime.diff(te.released_at, te.sent_at, :microsecond),
          release_us: DateTime.diff(te.released_at, msg.recv_at, :microsecond)
        ]
      ]
      |> Betty.write()
    end
  end

  ##
  ## Private
  ##

  defp device_last_seen_cs(seen_list, sent_at) do
    DevAlias.device_id(seen_list) |> Device.seen_at_cs(sent_at)
  end
end
