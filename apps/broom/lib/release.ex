defmodule Broom.Release do
  require Logger

  alias Broom.{State, Tracker, TrackerEntry}

  def handle_release(db_result_or_tracker_entry, %State{} = s) do
    case db_result_or_tracker_entry do
      %TrackerEntry{} = te -> State.release_entry(te, s)
      %_{acked: _} = schema -> release_via_schema(schema, s)
      {:ok, %_{acked: _} = schema} -> release_via_schema(schema, s)
      {:error, e} -> log_error_and_return_without_release(e, s)
    end
  end

  defp log_error_and_return_without_release(e, %State{} = s) do
    Logger.warn(["\n", inspect(e, pretty: true)])
    s
  end

  defp release_via_schema(%_{refid: refid} = schema, %State{} = s) do
    refid
    |> Tracker.get_refid_entry(s.tracker)
    |> TrackerEntry.apply_db_result(schema)
    |> State.release_entry(s)
  end
end
