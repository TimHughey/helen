defmodule Sally.Mutable.Handler do
  require Logger
  require Ecto.Query

  use Sally.Message.Handler, restart: :permanent, shutdown: 1000

  alias __MODULE__

  alias Alfred.MutableStatus, as: MutStatus
  alias Sally.{Command, DevAlias, Device, Execute, Immutable}
  alias Sally.Dispatch

  @impl true
  def finalize(%Dispatch{} = msg) do
    %Dispatch{msg | final_at: DateTime.utc_now()}
    |> tap(fn
      %Dispatch{valid?: false} = x -> Logger.warn("\n#{inspect(x, pretty: true)}")
      %Dispatch{valid?: true} = x -> Logger.debug("\n#{inspect(x, pretty: true)}")
    end)
  end

  @impl true
  def process(%Dispatch{category: "status"} = msg) do
    Logger.debug("BEFORE PROCESSING\n#{inspect(msg, pretty: true)}")
    Logger.debug("\n#{inspect(msg.data, pretty: true)}")

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:device, Device.changeset(msg, msg.host), Device.insert_opts())
    |> Ecto.Multi.run(:aliases, DevAlias, :load_aliases_with_last_cmd, [])
    |> Ecto.Multi.run(:aligned, Handler, :align_status, [msg])
    |> Ecto.Multi.run(:just_saw, Handler, :just_saw, [msg])
    |> Sally.Repo.transaction()
    |> check_result(msg)
    |> post_process()
    |> finalize()
  end

  @impl true
  def process(%Dispatch{category: "cmdack"} = msg) do
    alias Broom.TrackerEntry
    alias Sally.Repo

    Logger.debug("BEFORE PROCESSING\n#{inspect(msg, pretty: true)}")

    refid = List.first(msg.filter_extra)

    case Execute.ack_now(refid, msg.sent_at) do
      {:ok, %TrackerEntry{} = te} ->
        dev_alias = Repo.get!(DevAlias, te.dev_alias_id)
        dev_alias = DevAlias.just_saw(Repo, dev_alias, msg.sent_at)
        # ident = DB.Device.update_last_seen_at(dev_alias.device_id, msg.sent_at)

        {:ok,
         %{
           betty_rc:
             %Betty.Metric{
               measurement: "command",
               tags: %{module: __MODULE__, name: dev_alias.name, cmd: te.cmd},
               fields: %{
                 cmd_roundtrip_us: DateTime.diff(te.acked_at, te.sent_at, :microsecond),
                 cmd_total_us: DateTime.diff(te.released_at, te.sent_at, :microsecond),
                 release_us: DateTime.diff(te.released_at, msg.recv_at, :microsecond)
               }
             }
             |> Betty.write_metric(),
           just_saw: [dev_alias]
         }}

      error ->
        {:error, error}
    end
    |> check_result(msg)
    |> finalize()
  end

  @impl true
  def post_process(%Dispatch{valid?: true} = msg) do
    msg
  end

  @impl true
  def post_process(%Dispatch{valid?: false} = msg), do: msg

  def align_status(repo, changes, %Dispatch{} = msg) do
    alias Sally.Immutable

    pins = msg.data.pins
    reported_at = msg.sent_at

    for dev_alias <- changes.aliases, reduce: {:ok, []} do
      {:ok, acc} ->
        cmd = pin_status(pins, dev_alias.pio)
        status = Immutable.status(dev_alias.name, [])
        Logger.debug(inspect(status, pretty: true))

        case status do
          # there's a cmd pending, don't get in the way of ack or ack timeout
          %MutStatus{pending?: true} ->
            {:ok, acc}

          # accept the device reported cmd when our view of the cmd is unknown
          # (e.g. no cmd history, ttl is expired)
          %MutStatus{cmd: "unknown"} ->
            cmd = Command.reported_cmd_changeset(dev_alias, cmd, reported_at) |> repo.insert!(returning: true)

            {:ok, [cmd] ++ acc}

          _ ->
            {:ok, acc}
        end
    end
  end

  def just_saw(repo, changes, %Dispatch{} = msg) do
    alias Alfred.JustSaw

    for %DevAlias{} = dev_alias <- changes.aliases, reduce: {:ok, []} do
      {:ok, acc} ->
        DevAlias.just_saw(repo, dev_alias, msg.sent_at)
        JustSaw.new(Sally, changes.device.mutable, dev_alias) |> Alfred.just_saw_cast()

        {:ok, [dev_alias] ++ acc}
    end
  end

  defp check_result(txn_result, %Dispatch{} = msg) do
    case txn_result do
      {:ok, results} -> %Dispatch{msg | valid?: true, results: results}
      {:error, e} -> Dispatch.invalid(msg, e)
    end
  end

  defp pin_status(pins, pin_num) do
    for [pin, status] <- pins, pin == pin_num, reduce: nil do
      _ -> status
    end
  end
end
