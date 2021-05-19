defmodule Broom.Server do
  require Logger
  use GenServer

  alias Broom.{Opts, State, TrackMsg}

  @impl true
  def init(%Opts{} = opts) do
    alias Broom.{Metrics, Tracker}

    %State{
      tracker: Tracker.init(opts.orphan.after),
      opts: opts,
      metrics: Metrics.schedule_first(opts.metrics.interval)
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
  def handle_call({:count_reset, keys}, _from, %State{} = s) do
    alias Broom.Counts

    old_counts = s.counts

    %State{s | counts: Counts.reset(s.counts, keys)} |> reply({:reset, old_counts})
  end

  @impl true
  def handle_call(%TrackMsg{} = tm, _from, %State{} = s) do
    Broom.Track.handle_msg(tm, s)
    |> reply(:ok)
  end

  @impl true
  def handle_call({:change_metrics_interval, new_interval}, _from, %State{} = s) do
    alias Broom.Metrics

    # create a new State with the requested interval
    new_state = State.update_metrics_interval(s, Metrics.update_interval(s.metrics, new_interval))

    if Metrics.has_interval_changed?(s.metrics, new_state.metrics) do
      # the interval has changed, reschedule the next metrics report and return the new state
      %State{new_state | metrics: Metrics.schedule(new_state.metrics)}
      |> reply({:ok, new_interval})
    else
      # the interval requested was invalid, return the original state
      s |> reply({:failed, "invalid interval: #{new_interval}"})
    end
  end

  @impl true
  def handle_cast({:release, refid}, %State{} = s) do
    Broom.Release.handle_release(refid, s) |> noreply()
  end

  @impl true
  def handle_cast(%TrackMsg{} = tm, %State{} = s) do
    Broom.Track.handle_msg(tm, s) |> noreply()
  end

  @impl true
  def handle_info({:track_timeout, refid}, %State{} = s) do
    Broom.Track.handle_timeout(refid, s) |> noreply()
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

  # (1 of 3) handle pipeline: %State{} first, result second
  defp reply(%State{} = s, res), do: {:reply, res, s}

  # (2 of 2) handle pipeline: result is first, %State{} is second
  defp reply(res, %State{} = s), do: {:reply, res, s}

  # (3 of 3) assembles a reply based on a tuple (State, result) and rc
  defp reply({%State{} = s, result}, rc), do: {:reply, {rc, result}, s}

  defp reply_ok(%State{} = s), do: {:ok, s}
end
