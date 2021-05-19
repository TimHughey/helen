defmodule Broom.Metrics do
  alias __MODULE__

  alias Broom.Counts

  @interval_default_ms 300_000

  defstruct interval_ms: @interval_default_ms, last_at: :never, rc: :never, timer: :never

  def has_interval_changed?(%Metrics{} = m1, %Metrics{} = m2) do
    m1.interval_ms != m2.interval_ms
  end

  def put_interval_ms(%Metrics{} = m, interval) when is_binary(interval) do
    case EasyTime.iso8601_duration_to_ms(interval) do
      {:ok, ms} -> %Metrics{m | interval_ms: ms}
      _ -> m
    end
  end

  def schedule_first(interval) when is_binary(interval) do
    %Metrics{} |> put_interval_ms(interval) |> schedule()
  end

  def schedule(%Metrics{} = m) do
    cancel_timer_if_needed(m) |> start_timer()
  end

  def report(%Metrics{} = m, mod, %Counts{} = c) do
    mm = %Betty.Metric{measurement: "broom", fields: c, tags: %{mod: mod}}

    %Metrics{m | last_at: DateTime.utc_now(), rc: Betty.write_metric(mm), timer: :unscheduled}
    |> schedule()
  end

  def update_interval(%Metrics{} = m, iso8601) do
    # if the interval can be parsed then return the original iso8601 value and the updated metrics
    case EasyTime.iso8601_duration_to_ms(iso8601) do
      ms when is_integer(ms) -> {:ok, iso8601, %Metrics{m | interval_ms: ms}}
      {:failed, msg} -> {:failed, msg}
    end
  end

  # (1 of 2)
  defp cancel_timer_if_needed(%Metrics{timer: ref} = m) when is_reference(ref) do
    Process.cancel_timer(ref)

    %Metrics{m | timer: :unscheduled}
  end

  # (2 of 2)
  defp cancel_timer_if_needed(m), do: m

  defp start_timer(%Metrics{} = m) do
    %Metrics{timer: Process.send_after(self(), :report_metrics, m.interval_ms)}
  end
end
