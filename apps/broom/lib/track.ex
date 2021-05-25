defmodule Broom.Track do
  require Logger

  alias Broom.{State, Tracker, TrackerEntry, TrackMsg}

  # (1 of 2) db result reduced to just a schema
  @spec db_result(module(), Ecto.Schema.t(), keyword()) :: TrackerEntry.t()
  def db_result(mod, %_{acked: _} = schema, track_opts) do
    TrackMsg.create(mod, schema, track_opts) |> call_server()
  end

  # (2 of 2) db result tuple, validate it is :ok
  def db_result(mod, t, track_opts) when is_tuple(t) do
    case t do
      {:ok, schema} -> db_result(mod, schema, track_opts)
      {:error, e} -> {:failed, "db result error:\n#{inspect(e, pretty: true)}"}
    end
  end

  def handle_msg(%TrackMsg{} = tm, %State{} = s) do
    tm
    |> TrackMsg.ensure_track_timeout_ms(s.tracker.track_timeout_ms)
    |> TrackerEntry.make_entry()
    |> State.put_new_entry_in_tracker(s)
  end

  def handle_prune_refs(%Tracker{} = t, %State{} = s) do
    Tracker.prune_refs(t) |> State.put_tracker(s)
  end

  def handle_timeout(%TrackerEntry{} = te, %State{} = s) do
    te
    |> TrackerEntry.clear_timer()
    |> invoke_timeout_callback(s.opts.callback_mod)
    |> State.release_entry(s)
  end

  ##
  ## Private
  ##

  defp call_server(%TrackMsg{} = msg) do
    case msg do
      %{server_pid: nil} -> {:no_server, msg}
      %{server_pid: spid} -> GenServer.call(spid, msg)
    end
  end

  defp invoke_timeout_callback(%TrackerEntry{} = te, cb_mod) do
    cb_mod.track_timeout(te) |> TrackerEntry.apply_db_result(te)
  end
end
