defmodule Switch.Status do
  alias Switch.DB.Alias

  # (1 of 5) local and remote cmds are equal, this is goodness
  def check_cmd(%{local_cmd: %{cmd: lcmd}, remote_cmd: %{cmd: rcmd}} = m) when rcmd == lcmd do
    put_cmd(m, lcmd)
  end

  # (2 of 5) ttl is expired
  def check_cmd(%{ttl_expired: true, last_seen: last_seen} = m) do
    import Helen.Time.Helper, only: [elapsed_ms: 1]
    put_cmd_unknown(m) |> put_status(ttl_expired: elapsed_ms(last_seen))
  end

  # (3 of 5) last cmd was an orphan, populate cmd with unknown (ignore remote cmd)
  # NOTE: this does imply that once there is an orphan the cmd will always be unknown until
  #       there is a successful cmd
  def check_cmd(%{local_cmd: %{orphan: true}} = m) do
    put_cmd_unknown(m)
  end

  # (4 of 5) cmd is pending, populate cmd with the local cmd
  def check_cmd(%{pending: true, local_cmd: %{cmd: lcmd}} = m) do
    put_cmd(m, lcmd)
  end

  # (4 of 5) ttl isn't expired, last local cmd is acked (and not an orphan) yet remote and local cmd
  # aren't equal.  a remote restart likely occurred.  populate cmd with the remote cmd and note the
  # the mismatch.
  def check_cmd(%{remote_cmd: %{cmd: rcmd}, local_cmd: %{cmd: lcmd, acked: true, orphan: false}} = m)
      when rcmd != lcmd do
    put_status(m, mismatch: true) |> put_cmd(rcmd)
  end

  # (5 of 5) a strange situation, populate cmd with unknown
  def check_cmd(m), do: put_cmd_unknown(m)

  # (1 of 5) detect an invalid status
  def compare(%{invalid: msg}, _cmd, _opts), do: {:invalid, msg}

  # (2 of 5) detect TTL expired
  def compare(%{ttl_expired: true, ttl_ms: ttl_ms}, _cmd, _opts), do: {:ttl_expired, ttl_ms}

  # (3 of 5) handle pending
  def compare(%{pending: true} = status, cmd, opts) do
    import Map, only: [drop: 2]

    pending = opts[:ignore_pending]

    if pending do
      drop(status, [:pending]) |> compare(cmd, opts)
    else
      {:pending, status}
    end
  end

  # ( of 5) nominal case, just compare the cmds
  def compare(%{cmd: status_cmd}, %{cmd: spec_cmd}, _opts) when status_cmd == spec_cmd, do: :equal

  # (5 of 5) nothing has matched, not equal
  def compare(_status, _cmd, _opts), do: :not_equal

  def make_status(%Alias{} = a, opts) do
    import Alias, only: [status: 2]
    status(a, opts) |> check_cmd()
  end

  def put_cmd(status, cmd), do: put_in(status, [:cmd], cmd)

  def put_cmd_unknown(status), do: put_cmd(status, :unknown)

  def put_status(m, [{k, v}]) do
    put_in(m, [k], v)
  end
end
