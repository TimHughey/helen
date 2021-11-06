defmodule Illumination.Server do
  require Logger
  use GenServer

  alias Alfred.{NotifyMemo, NotifyTo}
  alias Illumination.{Schedule, State}
  alias Illumination.Schedule.Result

  @impl true
  def init(args) do
    state = %State{}

    initial_state = %State{
      alfred: args[:alfred] || state.alfred,
      module: args[:module] || __MODULE__,
      equipment: args[:equipment] || state.equipment,
      schedules: args[:schedules] || state.schedules,
      cmds: args[:cmds] || state.cmds,
      timezone: args[:timezone] || state.timezone
    }

    {:ok, initial_state, {:continue, :bootstrap}}
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
  def handle_continue(:bootstrap, %State{equipment: equipment} = s) do
    # important to calculate initial schedules some of which may be outdated depending on the
    # time of day the server is started.  subsequent schedule calculations will refresh
    # the out of date schedules.
    sched_opts = [timezone: s.timezone, datetime: Timex.now(s.timezone)]
    initial_schedules = Schedule.calc_points(s.schedules, sched_opts)

    # register for equipment notifications
    {:ok, notify_to} = s.alfred.notify_register(name: equipment, frequency: :all, link: true)

    # save the schedules and the notification registration
    [schedules: initial_schedules]
    |> State.save_schedules_and_result(s)
    |> State.save_equipment(notify_to)
    |> noreply()

    # NOTE: at this point the server is running and no further actions occur until an
    #       equipment notification is received
  end

  @impl true
  def handle_info({:activate, _schedule, _opts}, %State{} = s) do
    handle_info(:schedule, s)
  end

  @impl true
  def handle_info(
        {Broom, %Broom.TrackerEntry{refid: ref, acked_at: acked_at}},
        %State{result: %Result{schedule: schedule, exec: %Alfred.ExecResult{refid: ref}}} = s
      ) do
    [result: Schedule.handle_cmd_ack(schedule, acked_at, timezone: s.timezone)]
    |> State.save_schedules_and_result(s)
    |> noreply()
  end

  @impl true
  def handle_info({:finish, _schedule, _opts}, %State{} = s) do
    handle_info(:schedule, s)
  end

  @impl true
  def handle_info(:schedule, %State{} = s) do
    Result.cancel_timers_if_needed(s.result)

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

  # (1 of 3) handle equipment missing messages
  @impl true
  def handle_info({Alfred, %NotifyMemo{missing?: true} = memo}, %State{} = s) do
    Betty.app_error(s, equipment: memo.name, missing: true)
    |> State.update_last_notify_at()
    |> noreply()
  end

  # (2 of x) handle the first notification (result == nil) by simply performing a schedule
  @impl true
  def handle_info({Alfred, %NotifyMemo{}}, %State{result: nil} = s) do
    handle_info(:schedule, State.update_last_notify_at(s))
  end

  # (3 of 3) handle subsequent notifications (result != nil) comparing the equipment status
  # to the expected cmd (based on previous execute result)
  @impl true
  def handle_info(
        {Alfred, %Alfred.NotifyMemo{ref: ref} = memo},
        %State{equipment: %NotifyTo{ref: ref}, result: result} = s
      ) do
    alias Alfred.MutableStatus, as: MutStatus

    expected_cmd = Result.expected_cmd(result)
    status = s.alfred.status(memo.name)

    new_state = State.update_last_notify_at(s)

    case status do
      # skip check when cmd is pending
      %MutStatus{pending?: true} ->
        noreply(new_state)

      # do nothing when expected cmd matches status cmd
      %MutStatus{good?: true, cmd: cmd} when cmd == expected_cmd ->
        noreply(new_state)

      # anything else attempt to correct the mismatch by restarting
      _ ->
        Logger.warn("#{memo.name} cmd mismatch, restarting")
        {:stop, :normal, new_state}
    end
  end

  defp noreply(%State{} = s), do: {:noreply, s}
end