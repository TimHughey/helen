defmodule Alfred.MutableStatus do
  alias __MODULE__, as: Status

  defstruct name: nil,
            good?: false,
            found?: true,
            cmd: "unknown",
            cmd_extra: %{},
            status_at: nil,
            pending?: false,
            pending_refid: nil,
            ttl_expired?: false,
            error: :none

  @type status_error() :: :none | :unresponsive | :unknown_state
  @type t :: %__MODULE__{
          name: String.t(),
          good?: boolean(),
          found?: boolean(),
          cmd: String.t(),
          cmd_extra: map(),
          status_at: DateTime.t(),
          pending?: boolean(),
          pending_refid: String.t(),
          ttl_expired?: boolean(),
          error: status_error()
        }

  # (1 of 2) this status is good: ttl is ok, it is found and no error
  def finalize(%Status{error: :none, found?: true, ttl_expired?: false} = x) do
    %Status{x | good?: true}
  end

  # (2 of 2) something is wrong with this status
  def finalize(%Status{} = x), do: x

  def good(%_{cmds: [%_{cmd: cmd}]} = x) do
    %Status{
      name: x.name,
      cmd: cmd,
      status_at: x.device.last_seen_at
    }
  end

  def not_found(name), do: %Status{name: name, status_at: DateTime.utc_now(), found?: false}

  def pending(%_{cmds: [%_{} = cmd_schema]} = x) do
    %Status{
      name: x.name,
      cmd: cmd_schema.cmd,
      status_at: cmd_schema.sent_at,
      pending?: true,
      pending_refid: cmd_schema.refid
    }
  end

  def ttl_expired(%_{} = x) do
    %Status{name: x.name, status_at: x.device.last_seen_at, ttl_expired?: true}
  end

  def ttl_expired?(%Status{ttl_expired?: expired}), do: expired

  def unknown_state(%_{} = x) do
    %Status{
      name: x.name,
      cmd: "unknown",
      status_at: x.updated_at,
      error: :unknown_state
    }
  end

  def unresponsive(%_{} = x) do
    [%_{} = cmd_schema] = x.cmds

    %Status{
      name: x.name,
      cmd: "unknown",
      status_at: cmd_schema.acked_at,
      error: :unresponsive
    }
  end
end
