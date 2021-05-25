defmodule Broom.TrackerEntry do
  require Logger

  alias __MODULE__, as: Entry
  alias Broom.TrackMsg

  alias Broom.BaseTypes, as: Types

  defstruct cmd: nil,
            sent_at: nil,
            tracked_at: nil,
            alias_id: nil,
            refid: nil,
            acked: false,
            acked_at: nil,
            orphaned: false,
            notify_pid: nil,
            track_timeout_ms: nil,
            timer: nil,
            released: false,
            released_at: nil,
            module: nil,
            schema: nil,
            schema_id: nil

  @type t :: %__MODULE__{
          cmd: String.t(),
          sent_at: Types.datetime_or_nil(),
          tracked_at: Types.datetime_or_nil(),
          alias_id: Types.db_primary_id(),
          refid: String.t(),
          acked: boolean(),
          acked_at: Types.datetime_or_nil(),
          orphaned: boolean(),
          notify_pid: Types.pid_or_nil(),
          track_timeout_ms: Types.milliseconds_or_nil(),
          timer: Types.reference_or_nil(),
          released: boolean(),
          released_at: Types.datetime_or_nil(),
          module: Types.module_or_nil(),
          schema: TYpes.schema_or_nil(),
          schema_id: Types.db_primary_id()
        }

  # NOTE: invoked after track_timeout AND when entry is released via a db_result

  # (1 of 4) actual schema, apply to entry
  def apply_db_result(%_{acked: _} = schema, %Entry{} = te) do
    %Entry{te | acked: schema.acked, orphaned: schema.orphaned, acked_at: schema.acked_at}
  end

  # (1 of 4) support pipeline when the Entry is passed first
  def apply_db_result(%Entry{} = te, db_result_or_schema),
    do: apply_db_result(db_result_or_schema, te)

  # (3 of 4) good db result, apply the schema
  def apply_db_result({:ok, %_{acked: _} = schema}, %Entry{} = te),
    do: apply_db_result(schema, te)

  # (4 of 4) db error
  def apply_db_result({:error, e}, %Entry{} = te) do
    Logger.warn(["\n", inspect(e, pretty: true)])
    te
  end

  def clear_timer(%Entry{} = te) do
    if te.timer && Process.read_timer(te.timer) do
      Process.cancel_timer(te.timer)
    end

    %Entry{te | timer: nil}
  end

  def make_entry(%TrackMsg{schema: schema} = tm) do
    refid = schema.refid

    %Entry{
      cmd: schema.cmd,
      sent_at: schema.sent_at,
      tracked_at: DateTime.utc_now(),
      alias_id: schema.alias_id,
      refid: refid,
      acked: schema.acked,
      acked_at: schema.acked_at,
      orphaned: schema.orphaned,
      notify_pid: tm.notify_pid,
      track_timeout_ms: tm.track_timeout_ms,
      module: tm.module,
      schema: tm.schema.__struct__,
      schema_id: tm.schema.id
    }
    |> start_track_timeout_timer()
    |> release_immediately_if_needed()
  end

  def older_than?(%Entry{} = te, %DateTime{} = old_at) do
    DateTime.compare(te.released_at, old_at) == :lt
  end

  def release(%Entry{} = te) do
    %Entry{te | released: true, released_at: DateTime.utc_now()}
    |> clear_timer()
    |> notify_if_needed()
  end

  defp notify_if_needed(%Entry{notify_pid: pid} = te) do
    if pid, do: send(pid, {Broom, :release, te})

    te
  end

  # if the Entry is acked at time of creation then immediately cast ourself a msg to release it
  defp release_immediately_if_needed(%Entry{} = te) do
    if te.acked, do: GenServer.cast(self(), {:release, te})

    te
  end

  defp start_track_timeout_timer(%Entry{} = te) do
    %Entry{te | timer: Process.send_after(self(), {:track_timeout, te}, te.track_timeout_ms)}
  end
end
