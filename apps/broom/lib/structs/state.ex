defmodule Broom.State do
  alias __MODULE__

  alias Broom.{Counts, Metrics, Opts, Tracker}
  alias Broom.TrackerEntry, as: Entry

  defstruct tracker: %Tracker{}, counts: %Counts{}, metrics: %Metrics{}, opts: %Opts{}

  def put_in_tracker(%Entry{} = te, %State{tracker: t, counts: c} = s) do
    # return a tuple containing the updated State and the Entry (good for pipelining)
    {%State{s | tracker: Tracker.put_entry(te, t), counts: Counts.increment(:tracked, c)}, te}
  end

  # (1 of 2) support pipeline when Entry is updated before release
  def release_entry(%Entry{} = te, %State{} = s), do: release_entry(s, te)

  # (2 of 2) support pipeline when Entry is simply released
  def release_entry(%State{tracker: t, counts: c} = s, %Entry{} = te) do
    te = Entry.release(te)
    {%State{s | tracker: Tracker.remove_entry(te, t), counts: Counts.released_entry(te, c)}, te}
  end

  # (1 of 2) we have a valid iso8601 interval, pass it along to Opts
  def update_metrics_interval(%State{} = s, {:ok, iso8601, %Metrics{} = m}) do
    %State{s | metrics: m, opts: Opts.update_metrics_interval(s.opts, iso8601)}
  end

  # (2 of 2) we have an invalid iso8601 interval... no changes
  def update_metrics_interval(%State{} = s, {:failed, _msg}), do: s
end
