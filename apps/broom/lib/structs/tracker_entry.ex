defmodule Broom.TrackerEntry do
  alias __MODULE__, as: Entry
  alias Broom.TrackMsg

  defstruct cmd: nil,
            sent_at: nil,
            tracked_at: nil,
            alias_id: nil,
            refid: nil,
            acked: false,
            acked_at: nil,
            orphaned: false,
            notify_pid: nil,
            orphan_after_ms: nil,
            timer: nil,
            released: false,
            released_at: nil,
            module: nil,
            schema: nil,
            schema_id: nil

  def acked(%Entry{} = te, %DateTime{} = ack_at) do
    %Entry{te | acked: true, acked_at: ack_at}
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
      notify_pid: tm.notify_pid,
      orphan_after_ms: tm.orphan_after_ms,
      module: tm.module,
      schema: tm.schema.__struct__,
      schema_id: tm.schema.id
    }
    |> start_orphan_timer_if_needed()
    |> immediate_release_if_needed()
  end

  def orphaned(%Entry{} = te) do
    %Entry{te | orphaned: true}
  end

  def release(%Entry{} = te) do
    %Entry{te | released: true, released_at: DateTime.utc_now()} |> notify_if_needed()
  end

  defp immediate_release_if_needed(%Entry{} = te) do
    case te do
      %Entry{acked: true} -> release(te)
      _ -> te
    end
  end

  defp notify_if_needed(%Entry{notify_pid: nil} = te), do: te

  defp notify_if_needed(%Entry{notify_pid: pid} = te) do
    send(pid, {Broom, :release, te})

    te
  end

  # (1 of 2) not ack'ed, start an orphan timeout
  defp start_orphan_timer_if_needed(%Entry{acked: false} = te) do
    timer_ref = Process.send_after(self(), {:track_timeout, te.refid}, te.orphan_after_ms)

    %Entry{te | timer: timer_ref}
  end

  # (2 of 2) already acked, don't start a timer
  defp start_orphan_timer_if_needed(%Entry{} = te), do: te
end
