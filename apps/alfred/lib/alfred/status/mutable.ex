defmodule Alfred.MutableStatus do
  alias __MODULE__, as: Status

  defstruct name: nil,
            good?: false,
            found?: true,
            cmd: "unknown",
            extended: %{},
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
          extended: map() | struct(),
          status_at: DateTime.t(),
          pending?: boolean(),
          pending_refid: String.t(),
          ttl_expired?: boolean(),
          error: status_error()
        }

  # testing the below serves zero purpose as a unit test
  # rather, these are tested as part of integration testing
  # coveralls-ignore-start

  # (1 of 2) this status is good: ttl is ok, it is found and no error
  def finalize(%Status{error: :none, found?: true, ttl_expired?: false} = x) do
    %Status{x | good?: true}
  end

  # (2 of 2) something is wrong with this status
  def finalize(%Status{} = x), do: x

  def good(%{name: name, device: %{last_seen_at: last_seen_at}, cmds: [%{cmd: cmd}]}) do
    %Status{name: name, cmd: cmd, status_at: last_seen_at}
  end

  def not_found(name), do: %Status{name: name, status_at: DateTime.utc_now(), found?: false}

  def pending(%{name: name, cmds: [%{cmd: cmd, sent_at: sent_at, refid: refid}]}) do
    %Status{name: name, cmd: cmd, status_at: sent_at, pending?: true, pending_refid: refid}
  end

  def ttl_expired(%{name: name, device: %{last_seen_at: last_seen_at}}) do
    %Status{name: name, status_at: last_seen_at, ttl_expired?: true}
  end

  def ttl_expired?(%Status{ttl_expired?: expired}), do: expired

  def unknown_state(%{name: name, updated_at: updated_at}) do
    %Status{name: name, cmd: "unknown", status_at: updated_at, error: :unknown_state}
  end

  def unresponsive(%{name: name, cmds: [%{acked_at: acked_at}]}) do
    %Status{name: name, cmd: "unknown", status_at: acked_at, error: :unresponsive}
  end

  # coveralls-ignore-stop
end
