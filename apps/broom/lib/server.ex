defmodule Broom.Server do
  require Logger
  use GenServer

  alias Broom.{Opts, State, TrackerEntry, TrackMsg}

  @impl true
  def init(%Opts{} = opts) do
    alias Broom.{Metrics, Tracker}

    %State{
      tracker: Tracker.init(opts.track),
      opts: opts,
      metrics: Metrics.init(opts.metrics)
    }
    |> reply_ok()
  end

  def start_link(%Opts{} = opts) do
    # assemble the genserver opts
    genserver_opts = [name: opts.server.name] ++ opts.server.genserver
    GenServer.start_link(Broom.Server, opts, genserver_opts)
  end

  @impl true
  def handle_call({:counts}, _from, %State{} = s) do
    s.counts |> reply(s)
  end

  @impl true
  def handle_call({:counts_reset, keys}, _from, %State{} = s) do
    old_counts = s.counts

    %State{s | counts: Broom.Counts.reset(s.counts, keys)} |> reply({:reset, old_counts})
  end

  @impl true
  def handle_call({:get_refid_entry, refid}, _from, %State{} = s) do
    Broom.Tracker.get_refid_entry(refid, s.tracker) |> reply(s)
  end

  @impl true
  def handle_call(%TrackMsg{} = tm, _from, %State{} = s) do
    Logger.debug(["\n", inspect(tm, pretty: true), "\n"])

    Broom.Track.handle_msg(tm, s)
    |> reply(:ok)
  end

  @impl true
  def handle_call({:change_metrics_interval, new_interval}, _from, %State{} = s) do
    case State.update_metrics_interval(s, metrics_interval: new_interval) do
      {{:ok, _} = rc, %State{} = new_state} -> rc |> reply(new_state)
      failed -> failed |> reply(s)
    end
  end

  @impl true
  def handle_call({:release, x}, _from, %State{} = s) do
    Broom.Release.handle_release(x, s) |> reply()
  end

  @impl true
  def handle_cast({:release, x}, %State{} = s) do
    Broom.Release.handle_release(x, s) |> noreply()
  end

  @impl true
  def handle_cast(%TrackMsg{} = tm, %State{} = s) do
    Broom.Track.handle_msg(tm, s) |> noreply()
  end

  @impl true
  def handle_info(:prune_refs, %State{} = s) do
    Broom.Track.handle_prune_refs(s.tracker, s) |> noreply()
  end

  @impl true
  def handle_info({:track_timeout, %TrackerEntry{} = te}, %State{} = s) do
    Broom.Track.handle_timeout(te, s) |> noreply()
  end

  @impl true
  def handle_info(:report_metrics, %State{} = s) do
    alias Broom.Metrics

    %State{s | metrics: Metrics.report(s.metrics, s.opts.callback_mod, s.counts)}
    |> noreply()
  end

  ##
  ## GenServer Reply Helpers
  ##

  # (1 of 2) handle plain %State{}
  defp noreply(%State{} = s), do: {:noreply, s}

  # (2 of 2) support pipeline {%State{}, msg} -- return State and discard message
  defp noreply({%State{} = s, _msg}), do: {:noreply, s}

  # (1 of 4) handle pipeline: %State{} first, result second
  defp reply(%State{} = s, res), do: {:reply, res, s}

  # (2 of 4) handle pipeline: result is first, %State{} is second
  defp reply(res, %State{} = s), do: {:reply, res, s}

  # (3 of 4) assembles a reply based on a tuple (State, result) and rc
  defp reply({%State{} = s, result}, rc), do: {:reply, {rc, result}, s}

  # (4 of 4) assembles a reply based on a tuple {result, State}
  defp reply({%State{} = s, result}), do: {:reply, result, s}

  defp reply_ok(%State{} = s) do
    Logger.debug(["\n", inspect(s, pretty: true), "\n"])

    {:ok, s}
  end
end
