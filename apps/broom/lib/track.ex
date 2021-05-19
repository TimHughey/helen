defmodule Broom.Track do
  alias Broom.{State, Tracker, TrackerEntry, TrackMsg}

  def db_result(mod, {_rc, _schwma} = x, track_opts) do
    case x do
      {:ok, %_{acked: true} = cmd_schema} ->
        TrackMsg.create(mod, cmd_schema, track_opts) |> TrackerEntry.make_entry()

      {:ok, %_{} = cmd_schema} ->
        TrackMsg.create(mod, cmd_schema, track_opts) |> call_or_cast_msg() |> make_return_tuple()

      {:error, _x} ->
        {:failed, "received an error tuple"}
    end
  end

  def handle_msg(%TrackMsg{} = tm, %State{} = s) do
    tm
    |> TrackMsg.ensure_orphan_after_ms(s.tracker.orphan_after_ms)
    |> TrackerEntry.make_entry()
    |> State.put_in_tracker(s)
  end

  def handle_timeout(refid, %State{} = s) do
    callback_mod = s.opts.callback_mod

    refid
    |> Tracker.get_refid_entry(s.tracker)
    |> callback_mod.track_timeout()
    |> State.release_entry(s)
  end

  ##
  ## Private
  ##

  defp call_or_cast_msg(%TrackMsg{} = msg) do
    case msg do
      %{server_pid: nil} -> {:no_server, msg}
      %{notify_pid: nil, server_pid: spid} -> {:cast, GenServer.cast(spid, msg), msg}
      %{server_pid: spid} -> GenServer.call(spid, msg)
    end
  end

  defp make_return_tuple(x) do
    # 1. :ok is returned from GenServer.cast/2, assemble simple result
    # 2. {:ok, result} is returned from GenServer.call/2, return result
    # 3. {:no_server, mod} is returned when we can't find a GenServer for the module
    case x do
      {:cast, :ok, %TrackMsg{} = tm} -> {:ok, [track_requested: tm.schema.refid]}
      {:ok, _} = success -> success
      {:no_server, %TrackMsg{module: mod}} -> {:failed, "no server: #{inspect(mod)}"}
    end
  end
end
