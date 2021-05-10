defmodule PulseWidth.Status do
  use Timex

  alias PulseWidth.DB.Alias

  # (2 of 5) ttl is expired
  def check_cmd(%{ttl_expired: true, seen_at: seen_at} = m) do
    put_cmd_unknown(m) |> put_status(ttl_elapsed_ms: elapsed_ms(seen_at))
  end

  # (3 of 5) last cmd was an orphan, populate cmd with unknown (ignore remote cmd)
  # NOTE: this does imply that once there is an orphan the cmd will always be unknown until
  #       there is a successful cmd
  def check_cmd(%{cmd_last: %{orphan: true}} = m) do
    put_cmd_unknown(m)
  end

  # (4 of 5) cmd is pending, populate cmd with the local cmd and promote refid to top of status
  def check_cmd(%{cmd_last: %{pending: true} = lcm} = m) do
    put_status(m, refid: lcm.refid) |> put_cmd(lcm)
  end

  # (1 of 6) ruled out ttl expired, orphan/ack and found a perfect match
  def check_cmd(%{cmd_last: lcm, cmd_reported: rcm} = m) when lcm.cmd == rcm.cmd do
    put_cmd(m, lcm)
  end

  # (4 of 5) ttl isn't expired, ruled out last cmd orphan/ack yet remote and local cmd aren't equal.
  # a remote restart likely occurred.  populate cmd with the remote cmd and note  mismatch.
  def check_cmd(%{cmd_reported: %{cmd: rcmd} = rcm, cmd_last: %{cmd: lcmd}} = m)
      when rcmd != lcmd do
    put_status(m, mismatch: true) |> put_cmd(rcm)
  end

  # (5 of 5) a strange situation, populate cmd with unknown
  def check_cmd(m), do: put_cmd_unknown(m)

  # (1 of 5) detect an invalid status
  def compare(%{invalid: msg}, _cmd, _opts), do: {:invalid, msg}

  # (2 of 5) detect TTL expired
  def compare(%{ttl_expired: true, ttl_ms: ttl_ms}, _cmd, _opts), do: {:ttl_expired, ttl_ms}

  # (3 of 5) handle pending
  def compare(%{pending: true} = status, cmd, opts) do
    pending = opts[:ignore_pending]

    if pending do
      Map.delete(status, :pending) |> compare(cmd, opts)
    else
      {:pending, status}
    end
  end

  # ( of 5) nominal case, just compare the cmds
  def compare(%{cmd: cmd1}, %{cmd: cmd2}, _opts) when cmd1 == cmd2, do: :equal

  # (5 of 5) nothing has matched, not equal
  def compare(_status, _cmd, _opts), do: :not_equal

  def make_status(%Alias{} = a, opts) do
    Alias.status(a, opts) |> check_cmd()
  end

  defp elapsed_ms(dt) do
    # Timex.now() |> Timex.diff(dt, :duration) |> Duration.to_milliseconds(truncate: true)
    DateTime.utc_now() |> DateTime.diff(dt, :millisecond)
  end

  defp put_cmd(status, cmd_map) do
    want = Map.take(cmd_map, [:cmd, :pending])

    Map.merge(status, want)
  end

  defp put_cmd_unknown(status), do: put_cmd(status, %{cmd: "unknown"})

  defp put_status(m, [{k, v}]) do
    put_in(m, [k], v)
  end
end
