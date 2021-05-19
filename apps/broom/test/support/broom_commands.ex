defmodule BroomTester.Commands do
  @moduledoc false

  require Logger

  use Broom, schema: BroomTester.DB.Command, restart: :permanent, shutdown: 2000

  def counts, do: Broom.counts()
  def change_metrics_interval(new_interval), do: Broom.change_metrics_interval(new_interval)
  def track(this, opts), do: Broom.track(this, opts)

  def track_timeout(%TrackerEntry{schema_id: schema_id} = te) do
    # simulate acked and orphaned commands
    # 1, schema_ids less than 50,000 should be acked
    # 2. others should be orphaned
    case schema_id do
      x when x <= 50_000 -> TrackerEntry.acked(te, acked_at(te))
      _ -> TrackerEntry.orphaned(te)
    end

    # ["\n", inspect(te, pretty: true)] |> Logger.info()
  end

  # simulate acked_at as one millisecond before orphan after
  defp acked_at(%TrackerEntry{tracked_at: tracked_at, orphan_after_ms: skew}) do
    DateTime.add(tracked_at, skew - 1, :millisecond)
  end
end
