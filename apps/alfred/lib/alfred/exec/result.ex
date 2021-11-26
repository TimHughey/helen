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

  @type exec_rc :: :ok | :pending | :not_found | {:ttl_expired, pos_integer()} | {:invalid, String.t()}

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
    case opts[:rc] do
      x when is_nil(x) or x == :ok ->
        %ExecResult{
          name: ec.name,
          rc: :ok,
          cmd: ec.cmd,
          refid: opts[:refid],
          track_timeout_ms: opts[:track_timeout_ms],
          will_notify_when_released: if(is_boolean(opts[:will_notify]), do: opts[:will_notify], else: false),
          instruct: opts[:instruct]
        }

      x when is_atom(x) ->
        invalid(ec, x)
    end
  end

  def from_status(%MutableStatus{} = status) do
    case status do
      %MutableStatus{ttl_expired?: true} -> ttl_expired(status)
      %MutableStatus{found?: false} -> not_found(status)
    end
  end

  def invalid(%ExecCmd{} = ec, rc) when is_atom(rc) do
    er = %ExecResult{name: ec.name, cmd: ec.cmd}

    case rc do
      :callback_failed -> %ExecResult{er | rc: {:invalid, "callback failed"}}
      :immutable -> %ExecResult{er | rc: {:invalid, "must be a mutable"}}
      :missing -> %ExecResult{er | rc: {:invalid, "name is missing"}}
      :unknown -> %ExecResult{er | rc: {:invalid, "name is unknown"}}
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
      will_notify_when_released: if(is_pid(te.notify_pid), do: true, else: false),
      instruct: instruct
    }
  end

  def ttl_expired(%MutableStatus{name: name, status_at: at}) do
    rc = {:ttl_expired, DateTime.utc_now() |> DateTime.diff(at, :millisecond)}

    %ExecResult{name: name, rc: rc}
  end
end