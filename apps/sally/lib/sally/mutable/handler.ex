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
    |> Multi.update(:device, fn x -> DevAlias.device_id(x.seen_list) |> Device.seen_at_cs(sent_at) end)
    |> Repo.transaction()
  end

  @impl true
  def process(%Dispatch{category: "status", filter_extra: [_ident, "ok"]} = msg) do
    Logger.debug("BEFORE PROCESSING\n#{inspect(msg, pretty: true)}")

    case db_actions(msg) do
      {:ok, %{device: device, seen_list: seen_list} = txn_results} ->
        # NOTE: alert Alfred of just seen names after txn is complete
        Sally.just_saw(device, seen_list)
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
        %{device: device, seen_list: seen_list} = txn_results

        released_te = Execute.release(txn_results.command)
        write_ack_metrics(seen_list, released_te, msg)

        # NOTE: alert Alfred of just seen names after txn is complete
        Sally.just_saw(device, seen_list)
        |> Dispatch.save_seen_list(msg)
        |> Dispatch.valid(txn_results)

      {:error, error} ->
        Dispatch.invalid(msg, error)
    end
  end

  # Unwrap the DevAlias if needed
  # def write_ack_metrics([dev_alias], te, msg) do
  #   write_ack_metrics(dev_alias, te, msg)
  # end

  def write_ack_metrics([%DevAlias{} | _] = seen_list, te, msg) do
    for %DevAlias{} = dev_alias <- seen_list do
      %Betty.Metric{
        measurement: "command",
        tags: %{module: __MODULE__, name: dev_alias.name, cmd: te.cmd},
        fields: %{
          cmd_roundtrip_us: DateTime.diff(te.acked_at, te.sent_at, :microsecond),
          cmd_total_us: DateTime.diff(te.released_at, te.sent_at, :microsecond),
          release_us: DateTime.diff(te.released_at, msg.recv_at, :microsecond)
        }
      }
      |> Betty.write_metric()
    end
  end

  # @impl true
  # def post_process(%Dispatch{valid?: true} = msg) do
  #   msg
  # end
  #
  # @impl true
  # def post_process(%Dispatch{valid?: false} = msg), do: msg

  # def align_status(repo, changes, %Dispatch{} = msg) do
  #   alias Sally.Mutable
  #
  #   pins = msg.data.pins
  #   reported_at = msg.sent_at
  #
  #   for dev_alias <- changes.aliases, reduce: {:ok, []} do
  #     {:ok, acc} ->
  #       cmd = pin_status(pins, dev_alias.pio)
  #       status = Mutable.status(dev_alias.name, [])
  #       Logger.debug(inspect(status, pretty: true))
  #
  #       case status do
  #         # there's a cmd pending, don't get in the way of ack or ack timeout
  #         %MutStatus{pending?: true} ->
  #           {:ok, acc}
  #
  #         # accept the device reported cmd when our view of the cmd is unknown
  #         # (e.g. no cmd history, ttl is expired)
  #         %MutStatus{cmd: "unknown"} ->
  #           cmd = Command.reported_cmd_changeset(dev_alias, cmd, reported_at) |> repo.insert!(returning: true)
  #
  #           {:ok, [cmd] ++ acc}
  #
  #         %MutStatus{cmd: local_cmd} when local_cmd != cmd ->
  #           cmd = Command.reported_cmd_changeset(dev_alias, cmd, reported_at) |> repo.insert!(returning: true)
  #
  #           {:ok, [cmd] ++ acc}
  #
  #         _ ->
  #           {:ok, acc}
  #       end
  #   end
  # end

  # def just_saw(_repo, results) do
  #   case results do
  #     %{device: %Device{}, aliases: [_ | _]} -> Sally.just_saw(results.device, results.aliases)
  #     _ -> []
  #   end
  # end

  # defp check_result(txn_result, %Dispatch{} = msg) do
  #   case txn_result do
  #     {:ok, results} -> %Dispatch{msg | valid?: true, results: results}
  #     {:error, e} -> Dispatch.invalid(msg, e)
  #   end
  # end

  # defp pin_status(pins, pin_num) do
  #   for [pin, status] <- pins, pin == pin_num, reduce: nil do
  #     _ -> status
  #   end
  # end
end
