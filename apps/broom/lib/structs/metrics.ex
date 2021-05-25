defmodule Broom.Metrics do
  require Logger

  alias __MODULE__

  alias Broom.Counts
  alias Broom.MetricsOpts

  @interval_default_ms 300_000

  defstruct interval_ms: @interval_default_ms, last_at: :never, rc: :never, timer: :never

  @type last_at() :: DateTime.t() | :never
  @type metrics_rc() :: :never | tuple()
  @type metrics_timer() :: :never | :unscheduled | reference()
  @type t :: %__MODULE__{
          interval_ms: pos_integer(),
          last_at: last_at(),
          rc: metrics_rc(),
          timer: metrics_timer()
        }

  def init(%MetricsOpts{} = metrics_opts) do
    %Metrics{interval_ms: metrics_opts.interval |> EasyTime.iso8601_duration_to_ms()} |> schedule()
  end

  def report(%Metrics{} = m, mod, %Counts{} = c) do
    mm = %Betty.Metric{measurement: "broom", fields: c, tags: %{mod: mod}}

    %Metrics{m | last_at: DateTime.utc_now(), rc: Betty.write_metric(mm), timer: :unscheduled}
    |> schedule()
  end

  def update_opts(%Metrics{} = m, %MetricsOpts{} = new_opts) do
    %Metrics{m | interval_ms: new_opts.interval |> EasyTime.iso8601_duration_to_ms()}
    |> cancel_timer_if_needed()
    |> schedule()
  end

  # (1 of 2)
  defp cancel_timer_if_needed(%Metrics{timer: ref} = m) when is_reference(ref) do
    Process.cancel_timer(ref)

    %Metrics{m | timer: :unscheduled}
  end

  # (2 of 2)
  defp cancel_timer_if_needed(m), do: m

  defp schedule(%Metrics{} = m) do
    cancel_timer_if_needed(m) |> start_timer()
  end

  defp start_timer(%Metrics{} = m) do
    %Metrics{m | timer: Process.send_after(self(), :report_metrics, m.interval_ms)}
  end
end
