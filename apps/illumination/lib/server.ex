defmodule Illumination.Server do
  require Logger
  use GenServer

  alias Illumination.{Schedule, State}
  alias Illumination.Schedule.Result

  @impl true
  def init(args) do
    state = %State{}

    initial_state = %State{
      alfred: args[:alfred] || state.alfred,
      equipment: args[:equipment] || state.equipment,
      schedules: args[:schedules] || state.schedules,
      cmds: args[:cmds] || state.cmds,
      timezone: args[:timezone] || state.timezone
    }

    {:ok, initial_state, {:continue, :find_equipment}}
  end

  def start_link(start_args) do
    {module, args_rest} = Keyword.pop(start_args, :module)
    {start_args, _args_rest} = Keyword.pop(args_rest, :start_args)

    server_opts = [name: module]

    GenServer.start_link(Illumination.Server, start_args, server_opts)
  end

  @impl true
  def handle_call(:restart, _from, %State{} = s) do
    {:stop, :normal, {:restarting, self()}, s}
  end

  @impl true
  def handle_continue(:find_equipment, %State{} = s) do
    # s = State.finding_equipment(s)
    handle_info(:find_equipment, s)
  end

  @impl true
  def handle_continue(:first_schedule, %State{} = s) do
    # s = State.first_schedule(s)
    handle_info(:schedule, s)
  end

  @impl true
  def handle_info(
        {Broom, :release, %Broom.TrackerEntry{refid: ref, acked_at: acked_at}},
        %State{result: %Result{schedule: schedule, exec: %Alfred.ExecResult{refid: ref}}} = s
      ) do
    Schedule.handle_cmd_ack(schedule, acked_at, timezone: s.timezone)
    |> State.save_result(s)
    |> noreply()
  end

  @impl true
  def handle_info({:finish, _schedule, _opts}, %State{} = s) do
    handle_info(:schedule, s)
  end

  @impl true
  def handle_info(:find_equipment, %State{equipment: equipment} = s) do
    reg = s.alfred.notify_register(equipment, frequency: :all, link: true)

    case reg do
      {:ok, %Alfred.NotifyTo{} = x} ->
        State.save_equipment(x, s) |> noreply_continue(:first_schedule)

      {:failed, _msg} ->
        Process.send_after(self(), :find_equipment, 1900)
        s |> noreply()
    end
  end

  @impl true
  def handle_info(:schedule, %State{} = s) do
    sched_opts = [
      alfred: s.alfred,
      equipment: s.equipment.name,
      timezone: s.timezone,
      datetime: Timex.now(s.timezone),
      cmds: s.cmds
    ]

    latest_schedules = Schedule.calc_points(s.schedules, sched_opts)
    active_next = Schedule.find_active_and_next(latest_schedules, sched_opts)
    result = Schedule.effectuate(active_next, sched_opts)

    [schedules: latest_schedules, result: result]
    |> State.save_schedules_and_result(s)
    |> noreply()
  end

  @impl true
  def handle_info({Alfred, :notify, %Alfred.NotifyMemo{} = _memo}, %State{} = s) do
    noreply(s)
  end

  defp noreply(%State{} = s), do: {:noreply, s}
  defp noreply_continue(%State{} = s, term), do: {:noreply, s, {:continue, term}}
end
