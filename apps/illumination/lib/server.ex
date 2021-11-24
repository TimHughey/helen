defmodule Illumination.Server do
  require Logger
  use GenServer

  alias Alfred.Notify.{Memo, Ticket}
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
  def handle_continue(:bootstrap, %State{} = s) do
    # important to calculate initial schedules some of which may be outdated depending on the
    # time of day the server is started.  subsequent schedule calculations will refresh
    # the out of date schedules.
    sched_opts = [timezone: s.timezone, datetime: Timex.now(s.timezone)]
    initial_schedules = Schedule.calc_points(s.schedules, sched_opts)

    # register for equipment notifications
    register_result = s.alfred.notify_register(name: s.equipment, frequency: :all, link: true)

    case register_result do
      {:ok, ticket} ->
        # save the schedules and the notification ticket
        [schedules: initial_schedules]
        |> State.save_schedules_and_result(s)
        |> State.save_equipment(ticket)
        |> noreply()

      {:no_server, _} ->
        {:stop, :normal, s}
    end

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
  def handle_info({Alfred, %Memo{missing?: true} = memo}, %State{} = s) do
    Betty.app_error(s, equipment: memo.name, missing: true)
    |> State.update_last_notify_at()
    |> noreply()
  end

  # (2 of x) handle the first notification (result == nil) by simply performing a schedule
  @impl true
  def handle_info({Alfred, %Memo{}}, %State{result: nil} = s) do
    handle_info(:schedule, State.update_last_notify_at(s))
  end

  # (3 of 3) handle subsequent notifications (result != nil) comparing the equipment status
  # to the expected cmd (based on previous execute result)
  @impl true
  def handle_info(
        {Alfred, %Memo{ref: ref} = memo},
        %State{equipment: %Ticket{ref: ref}, result: result} = s
      ) do
    alias Alfred.MutableStatus, as: MutStatus

    expected_cmd = Result.expected_cmd(result)
    status = s.alfred.status(memo.name)

    case status do
      # skip check when cmd is pending and don't update last notify
      %MutStatus{pending?: true} = _x ->
        noreply(s)

      # do nothing when expected cmd matches status cmd
      %MutStatus{good?: true, cmd: cmd} when cmd == expected_cmd ->
        State.update_last_notify_at(s) |> noreply()

      # anything else attempt to correct the mismatch by restarting
      status ->
        {:stop, :normal, tap(s, fn x -> log_cmd_mismatch(x, status) end)}
    end
  end

  defp log_cmd_mismatch(%State{result: result} = s, status) do
    %Result{queue_timer: qtimer, run_timer: rtimer} = result
    qt_ms = if is_reference(qtimer), do: Process.read_timer(qtimer), else: :unset
    rt_ms = if is_reference(rtimer), do: Process.read_timer(rtimer), else: :unset

    [
      "\n",
      "queue_timer_ms(#{qt_ms}) run_timer_ms(#{rt_ms})",
      "\n",
      "#{inspect(status, pretty: true)}",
      "\n",
      "#{inspect(s, pretty: true)}"
    ]
    |> IO.iodata_to_binary()
    |> Logger.warn()
  end

  defp noreply(%State{} = s), do: {:noreply, s}
end
