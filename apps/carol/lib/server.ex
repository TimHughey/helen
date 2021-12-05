defmodule Carol.Server do
  require Logger
  use GenServer

  alias __MODULE__
  alias Alfred.{ExecCmd, ExecResult}
  alias Alfred.Notify.Memo
  alias Broom.TrackerEntry
  alias Carol.{Schedule, State}
  alias Carol.Schedule.Result

  @impl true
  def init(args) do
    if args[:server_name] do
      Process.register(self(), args[:server_name])
      {:ok, State.new(args), {:continue, :bootstrap}}
    else
      {:stop, :missing_server_name}
    end
  end

  def call(msg, server) when is_pid(server) or is_atom(server) do
    GenServer.call(server, msg)
  rescue
    _ -> {:no_server, server}
  catch
    :exit, _ -> {:no_server, server}
  end

  def child_spec(opts) do
    {id, opts_rest} = Keyword.pop(opts, :id)
    {restart, opts_rest} = Keyword.pop(opts_rest, :restart, :permanent)

    final_opts = Keyword.put(opts_rest, :server_name, id)

    %{id: id, start: {Server, :start_link, [final_opts]}, restart: restart}
  end

  def start_link(start_args) do
    GenServer.start_link(Server, start_args)
  end

  @impl true
  def handle_call(:restart, _from, %State{} = s) do
    {:stop, :normal, :restarting, s}
  end

  @impl true
  def handle_continue(:bootstrap, %State{} = s) do
    # some schedules could be expired depending on the time of day the server is started
    # so perform an intiial calculation
    sched_opts = [timezone: s.timezone, datetime: Timex.now(s.timezone)]

    s.schedules
    |> Schedule.calc_points(sched_opts)
    |> State.save_schedules(s)
    |> State.start_notifies()
    |> noreply()

    # NOTE: at this point the server is running and no further actions occur until an
    #       equipment notification is received
  end

  @impl true
  def handle_info({:activate, _schedule, _opts}, %State{} = s) do
    handle_info(:schedule, s)
  end

  @impl true
  def handle_info({Broom, %TrackerEntry{cmd: "off"}}, %State{} = s) do
    # ignore release of "off" cmds

    noreply(s)
  end

  @impl true
  def handle_info(
        {Broom, %TrackerEntry{refid: ref} = te},
        %State{result: %Result{exec: %ExecResult{refid: ref}}} = s
      ) do
    Schedule.handle_cmd_ack(s.result.schedule, te.acked_at, timezone: s.timezone)
    |> State.save_result(s)
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
      equipment: s.equipment,
      timezone: s.timezone,
      datetime: Timex.now(s.timezone),
      cmd_inactive: s.cmd_inactive
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
    [server_name: s.server_name, equipment: memo.name, missing: true]
    |> Betty.app_error_v2(passthrough: s)
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
  def handle_info({Alfred, %Memo{} = memo}, %State{} = s) do
    alias Alfred.MutableStatus, as: MutStatus

    %ExecCmd{cmd: expected_cmd} = Result.expected_cmd(s.result)
    status = s.alfred.status(memo.name)

    case status do
      # skip check when cmd is pending and don't update last notify
      %MutStatus{pending?: true} = _x ->
        s

      # do nothing when expected cmd matches status cmd
      %MutStatus{good?: true, cmd: cmd} when cmd == expected_cmd ->
        State.update_last_notify_at(s)

      # anything else attempt to correct the mismatch by restarting
      %MutStatus{cmd: cmd, name: name} ->
        [server_name: s.server_name, cmd_mismatch: true, equipment: name, cmd: cmd]
        |> then(fn tags -> Betty.app_error_v2(tags, passthrough: s) end)
        |> then(fn state -> {:stop, :normal, state} end)
    end
    |> noreply()
  end

  defp noreply(%State{} = s), do: {:noreply, s}
  defp noreply({:stop, :normal, s}), do: {:stop, :normal, s}
end
