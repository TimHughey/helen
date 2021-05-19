defmodule Broom.Release do
  alias Broom.State

  def db_result(mod, {_rc, _schwma} = x) do
    server_pid = GenServer.whereis(mod)

    case {server_pid, x} do
      {nil, _} -> {:no_server, mod}
      {pid, {:ok, %_{refid: refid}}} -> {GenServer.cast(pid, {:release, refid}), refid}
      {:error, _x} -> {:failed, "received an error tuple"}
    end
  end

  def handle_release(refid, %State{} = s) do
    alias Broom.{Tracker, TrackerEntry}

    case Tracker.get_refid_entry(s.tracker, refid) do
      %TrackerEntry{} = te -> State.release_entry(s, te)
      _ -> s
    end
  end
end
