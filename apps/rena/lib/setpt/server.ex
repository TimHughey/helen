defmodule Rena.SetPt.Server do
  require Logger
  use GenServer

  alias __MODULE__
  alias Alfred.ExecResult
  alias Alfred.NotifyMemo, as: Memo
  alias Broom.TrackerEntry
  alias Rena.SetPt.State

  @impl true
  def init(args) do
    state = %State{}

    cmds = %{active: args[:cmds][:active], inactive: args[:cmds][:inactive]}

    initial_state = %State{
      alfred: args[:alfred] || state.alfred,
      server_name: args[:name],
      equipment: args[:equipment] || state.equipment,
      sensors: args[:sensors] || state.sensors,
      sensor_range: args[:range] || state.sensor_range,
      cmds: cmds,
      timezone: args[:timezone] || state.timezone
    }

    {:ok, initial_state, {:continue, :bootstrap}}
  end

  def start_link(start_args) do
    server_opts = [name: start_args[:name]]

    GenServer.start_link(Server, start_args, server_opts)
  end

  @impl true
  def handle_continue(:bootstrap, %State{} = s) do
    {:ok, nt} = s.alfred.notify_register(name: s.equipment, frequency: :all, link: true)

    State.save_equipment(s, nt)
    |> noreply()

    # NOTE: at this point the server is running and no further actions occur until an
    #       equipment notification is received
  end

  # (1 of 2) handle missing messages
  @impl true
  def handle_info({Alfred, %Memo{missing?: true} = memo}, %State{} = s) do
    Betty.app_error(s.server_name, equipment: memo.name, missing?: true)

    State.update_last_notify_at(s) |> noreply()
  end

  # (2 of 2) handle normal notify messages
  @impl true
  def handle_info({Alfred, %Memo{missing?: false} = memo}, %State{} = s) do
    alias Rena.Sensor
    alias Rena.SetPt.Cmd

    opts = [alfred: s.alfred, server_name: s.server_name]
    sensor_results = Sensor.range_compare(s.sensors, s.sensor_range, opts)

    Cmd.make(memo.name, sensor_results, opts)
    |> Cmd.effectuate(opts)
    |> State.update_last_exec(s)
    |> State.update_last_notify_at()
    |> noreply()
  end

  @impl true
  def handle_info({Broom, %TrackerEntry{} = te}, %State{last_exec: %ExecResult{} = er} = s) do
    want_refid = er.refid

    case te do
      %TrackerEntry{refid: refid, acked: true, acked_at: at} when refid == want_refid ->
        State.update_last_exec(at, s)

      %TrackerEntry{refid: refid, acked: false} when refid == want_refid ->
        Betty.app_error(s, equipment: s.equipment, ack_fail: true)
        |> State.update_last_exec(:failed)

      %TrackerEntry{} ->
        Betty.app_error(s, equipment: s.equipment, unknown_refid: true)
        |> State.update_last_exec(:failed)
    end
    |> noreply()
  end

  @impl true
  def handle_info({Broom, %TrackerEntry{} = te}, %State{} = s) do
    last_exec = fn -> inspect(s.last_exec, pretty: true) end
    Logger.warn("tracker entry msg failed\nref=#{te.refid}\nlast_exec=#{last_exec.()}")

    noreply(s)
  end

  defp noreply(%State{} = s), do: {:noreply, s}
end
