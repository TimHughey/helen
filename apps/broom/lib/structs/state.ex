defmodule Broom.State do
  require Logger

  alias __MODULE__

  alias Broom.{Counts, Metrics, Opts, Tracker}
  alias Broom.TrackerEntry, as: Entry

  defstruct tracker: %Tracker{}, counts: %Counts{}, metrics: %Metrics{}, opts: %Opts{}

  def put_new_entry_in_tracker(%Entry{} = te, %State{tracker: t, counts: c} = s) do
    # return a tuple containing the updated State and the Entry (good for pipelining)
    {%State{s | tracker: Tracker.put_entry(te, t), counts: Counts.increment(:tracked, c)}, te}
  end

  def put_tracker(%Tracker{} = t, %State{} = s), do: %State{s | tracker: t}

  # (1 of 2) support pipeline when Entry is updated before release
  def release_entry(%Entry{} = te, %State{} = s), do: release_entry(s, te)

  # (2 of 2) support pipeline when Entry is simply released
  def release_entry(%State{tracker: t, counts: c} = s, %Entry{} = te) do
    te = Entry.release(te)
    {%State{s | tracker: Tracker.release_entry(te, t), counts: Counts.released_entry(te, c)}, te}
  end

  # (1 of 2) we have a valid iso8601 interval, pass it along to Opts
  def update_metrics_interval(%State{} = s, opts) do
    case Opts.update_metrics(s.opts, opts) do
      {:ok, %Opts{} = o} ->
        metrics_opts = Opts.metrics(o)
        new_state = %State{s | opts: o, metrics: Metrics.update_opts(s.metrics, metrics_opts)}

        Logger.debug(["\n", inspect(new_state, pretty: true)])

        {{:ok, metrics_opts}, new_state}

      {:failed, _} = rc ->
        rc
    end
  end
end
