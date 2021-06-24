defmodule Sally.PulseWidth.Handler do
  require Logger
  require Ecto.Query

  use Sally.Message.Handler, restart: :permanent, shutdown: 1000

  alias __MODULE__

  alias Sally.{DevAlias, Device, Execute}
  alias Sally.Dispatch, as: Msg
  # alias Sally.Host.Instruct
  # alias Sally.PulseWidth

  @impl true
  def finalize(%Msg{} = msg) do
    log = fn x ->
      Logger.debug("\n#{inspect(x, pretty: true)}")
      x
    end

    %Msg{msg | final_at: DateTime.utc_now()} |> log.()
  end

  @impl true
  def process(%Msg{category: "status"} = msg) do
    Logger.debug("BEFORE PROCESSING\n#{inspect(msg, pretty: true)}")
    Logger.debug("\n#{inspect(msg.data, pretty: true)}")

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:device, Device.changeset(msg, msg.host), Device.insert_opts())
    |> Ecto.Multi.run(:aliases, DevAlias, :load_aliases_with_last_cmd, [])
    |> Sally.Repo.transaction()
    |> tap(fn x -> Logger.debug("\n#{inspect(msg.data)}\n#{inspect(x, pretty: true)}") end)
    |> check_result(msg)
    |> post_process()
    |> finalize()
  end

  @impl true
  def process(%Msg{category: "cmdack"} = msg) do
    alias Broom.TrackerEntry
    alias Sally.Repo

    Logger.debug("BEFORE PROCESSING\n#{inspect(msg, pretty: true)}")

    refid = List.first(msg.filter_extra)

    case Execute.ack_now(refid, msg.sent_at) do
      {:ok, %TrackerEntry{} = te} ->
        dev_alias = Repo.get!(DevAlias, te.dev_alias_id)
        # ident = DB.Device.update_last_seen_at(dev_alias.device_id, msg.sent_at)

        metric = %Betty.Metric{
          measurement: "command",
          tags: %{module: __MODULE__, name: dev_alias.name, cmd: te.cmd},
          fields: %{
            cmd_roundtrip_us: DateTime.diff(te.acked_at, te.sent_at, :microsecond),
            cmd_total_us: DateTime.diff(te.released_at, te.sent_at, :microsecond),
            release_us: DateTime.diff(te.released_at, msg.recv_at, :microsecond)
          }
        }

        Betty.write_metric(metric) |> inspect(pretty: true) |> Logger.info()

        msg |> finalize()

      error ->
        inspect(error, pretty: true) |> Logger.warn()

        # TODO properly fill out this error
        msg |> finalize()
    end
  end

  @impl true
  def post_process(%Msg{valid?: true} = msg) do
    msg
  end

  @impl true
  def post_process(%Msg{valid?: false} = msg), do: msg

  defp check_result(txn_result, %Msg{} = msg) do
    case txn_result do
      {:ok, _results} -> %Msg{msg | valid?: true}
      {:error, e} -> Msg.invalid(msg, e)
    end
  end
end
