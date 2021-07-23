defmodule Alfred.ExecResult do
  alias __MODULE__

  alias Alfred.ExecCmd
  alias Alfred.MutableStatus

  defstruct name: nil,
            rc: nil,
            cmd: "unknown",
            refid: nil,
            track_timeout_ms: nil,
            will_notify_when_released: false,
            instruct: nil

  @type(exec_rc :: :ok | :not_found | :tty_expired, {:invalid, String.t()} | {:error, any()})

  @type t :: %__MODULE__{
          name: String.t(),
          rc: exec_rc(),
          cmd: String.t(),
          refid: nil | String.t(),
          track_timeout_ms: nil | pos_integer(),
          will_notify_when_released: boolean(),
          instruct: nil | struct()
        }

  def error(name, rc), do: %ExecResult{name: name, rc: rc}

  def from_cmd(%ExecCmd{} = ec, opts) do
    %ExecResult{
      name: ec.name,
      rc: opts[:rc] || :ok,
      cmd: ec.cmd,
      refid: opts[:refid],
      track_timeout_ms: opts[:track_timeout_ms],
      will_notify_when_released: if(is_boolean(opts[:will_notify]), do: opts[:will_notify], else: false),
      instruct: opts[:instruct]
    }
  end

  def from_status(%MutableStatus{} = status) do
    case status do
      %MutableStatus{ttl_expired?: true} -> ttl_expired(status)
      %MutableStatus{found?: false} -> not_found(status)
    end
  end

  def invalid(%ExecCmd{name: name, invalid_reason: x}), do: %ExecResult{name: name, rc: {:invalid, x}}
  def not_found(%MutableStatus{name: name}), do: %ExecResult{name: name, cmd: "unknown", rc: :not_found}
  def no_change(%ExecCmd{name: name, cmd: cmd}), do: %ExecResult{name: name, cmd: cmd, rc: :ok}

  def ok(%ExecCmd{name: name, instruct: instruct}, %_{} = te) do
    %ExecResult{
      name: name,
      rc: :ok,
      cmd: te.cmd,
      refid: te.refid,
      track_timeout_ms: te.track_timeout_ms,
      will_notify_when_released: te.notify_pid && true,
      instruct: instruct
    }
  end

  def ttl_expired(%MutableStatus{name: name, status_at: at}) do
    rc = {:ttl_expired, DateTime.utc_now() |> DateTime.diff(at, :millisecond)}

    %ExecResult{name: name, rc: rc}
  end
end
