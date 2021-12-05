defmodule Illumination.State do
  alias __MODULE__

  alias Alfred.ExecCmd
  alias Alfred.Notify.Ticket

  alias Illumination.Schedule
  alias Illumination.Schedule.Result

  @cmd_inactive %ExecCmd{cmd: "off"} |> ExecCmd.add([:notify])

  defstruct alfred: Alfred,
            server_name: :none,
            schedules: [],
            equipment: "unset",
            cmd_inactive: @cmd_inactive,
            ticket: :none,
            result: nil,
            last_notify_at: nil,
            timezone: "America/New_York"

  @type t :: %State{
          alfred: module(),
          server_name: :none | module(),
          schedules: list(),
          equipment: String.t(),
          cmd_inactive: ExecCmd.t(),
          ticket: Ticket.t(),
          result: Schedule.Result.t(),
          last_notify_at: DateTime.t(),
          timezone: Calendar.time_zone()
        }

  @allowed_args [:alfred, :server_name, :equipment, :cmd_inactive, :schedules]
  def new(args) do
    {final_args, _} = Keyword.split(args, @allowed_args)

    struct(State, final_args)
    |> finalize_cmds()
  end

  def save_ticket(ticket_rc, %State{} = s) do
    case ticket_rc do
      x when is_atom(x) -> %State{s | ticket: x}
      {:ok, x} -> %State{s | ticket: x}
      {:no_server, _} -> {:stop, :normal, s}
    end
  end

  def save_result(%Result{} = result, s) do
    [result: result] |> save_schedules_and_result(s)
  end

  def save_schedules(schedules, s) do
    [schedules: schedules] |> save_schedules_and_result(s)
  end

  def save_schedules_and_result(to_save, s) when is_list(to_save) do
    to_save
    |> Keyword.take([:schedules, :result])
    |> then(fn save_opts -> struct(s, save_opts) end)
  end

  def start_notifies(%State{ticket: ticket} = s) do
    case ticket do
      x when x in [:none, :pause] ->
        [name: s.equipment, frequency: :all, link: true]
        |> s.alfred.notify_register()
        |> save_ticket(s)

      %Ticket{} ->
        s
    end
  end

  def update_last_notify_at(s), do: struct(s, last_notify_at: Timex.now())

  defp finalize_cmds(%State{schedules: schedules, equipment: name} = s) do
    cmd_inactive = ExecCmd.add_name(s.cmd_inactive, s.equipment)

    for %Schedule{start: start, finish: finish} = schedule <- schedules do
      start_cmd = ExecCmd.add_name(start.cmd, name) |> ExecCmd.add([:notify, :force])
      finish_cmd = ExecCmd.add_name(finish.cmd, name) |> ExecCmd.add([:notify, :force])

      [start: struct(start, cmd: start_cmd), finish: struct(finish, cmd: finish_cmd)]
      |> then(fn fields -> struct(schedule, fields) end)
    end
    |> Enum.reverse()
    |> then(fn schedules -> struct(s, cmd_inactive: cmd_inactive, schedules: schedules) end)
  end
end
