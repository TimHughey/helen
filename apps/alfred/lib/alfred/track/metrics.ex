defmodule Alfred.Track.Metrics do
  @moduledoc false

  require Logger
  use GenServer

  defstruct interval_ms: 60_000,
            start_at: nil,
            last_report_at: Timex.epoch(),
            tracked: 0,
            released: 0,
            timeout: 0,
            errors: 0

  def count(%Alfred.Track{} = track) do
    GenServer.cast(__MODULE__, {:count, track})
  end

  @counts_default [:tracked, :released, :timeout, :errors]
  def counts(metrics \\ @counts_default)
  def counts(metrics) when is_atom(metrics), do: counts([metrics])
  def counts(metrics) when is_list(metrics), do: GenServer.call(__MODULE__, {:counts, metrics})

  @impl true
  def init(opts) do
    {metrics_interval, _opts_rest} = Keyword.pop(opts, :metrics_interval, "PT1M")

    state = struct(__MODULE__, start_at: now(), interval_ms: to_ms(metrics_interval))

    {:ok, state, timeout_ms(state)}
  end

  @doc false
  def start_link(args), do: GenServer.start_link(__MODULE__, args, name: __MODULE__)

  @impl true
  def handle_call({:counts, metrics}, _from, state) do
    Map.take(state, metrics)
    |> Enum.into([])
    |> reply(state)
  end

  @impl true
  @metric_fields [:tracked, :released, :timeout, :errors]
  def handle_continue(:report_metrics, state) do
    tags = [module: __MODULE__]
    fields = Map.take(state, @metric_fields)

    {:ok, _point} = Betty.runtime_metric(tags, fields)

    struct(state, last_report_at: Timex.now())
    |> noreply()
  end

  @impl true
  def handle_cast({:count, track}, state) do
    case track do
      %{at: %{timeout: %DateTime{}}} -> update_count(:timeout, state)
      %{at: %{released: %DateTime{}}} -> update_count(:released, state)
      %{at: %{tracked: %DateTime{}}} -> update_count(:tracked, state)
      _ -> update_count(:error, state)
    end
    |> noreply()
  end

  @impl true
  def handle_info(:timeout, state) do
    state = struct(state, last_report_at: now())

    {:noreply, state, {:continue, :report_metrics}}
  end

  # Count Updaters

  @doc false
  def update_count(what, state) do
    %{^what => count} = state

    struct(state, [{what, count + 1}])
  end

  @doc false
  def now, do: Timex.now()

  @doc false
  def timeout_ms(%{last_report_at: at, interval_ms: interval_ms}) do
    elapsed_ms = Timex.diff(now(), at, :milliseconds)

    if elapsed_ms > interval_ms, do: 0, else: interval_ms - elapsed_ms
  end

  @doc false
  def noreply(state) do
    timeout_ms = timeout_ms(state)

    # NOTE: ensure that a report is performed in case the server is flooded
    if timeout_ms == 0 do
      {:noreply, state, {:continue, :timeout}}
    else
      {:noreply, state, timeout_ms}
    end
  end

  @doc false
  def reply(rc, %__MODULE__{} = state), do: {:reply, rc, state, timeout_ms(state)}
  def reply(%__MODULE__{} = state, rc), do: {:reply, rc, state, timeout_ms(state)}

  @doc false
  def to_ms(<<"PT"::binary, _rest::binary>> = iso8601) do
    Timex.Duration.parse!(iso8601) |> Timex.Duration.to_milliseconds(truncate: true)
  end
end
