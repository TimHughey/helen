defmodule Carol.State do
  alias __MODULE__

  alias Alfred.ExecResult
  alias Alfred.Notify.Ticket

  alias Carol.{Playlist, Program}

  defstruct alfred: Alfred,
            server_name: :none,
            equipment: :none,
            programs: [],
            playlist: :none,
            cmd_live: :none,
            ticket: :none,
            exec_result: :none,
            notify_at: :none,
            timezone: "America/New_York"

  @type t :: %State{
          alfred: module(),
          server_name: :none | module(),
          equipment: String.t(),
          programs: [Program.t(), ...],
          playlist: map(),
          cmd_live: :none | String.t(),
          ticket: Ticket.t(),
          exec_result: %ExecResult{},
          notify_at: DateTime.t(),
          timezone: Calendar.time_zone()
        }

  @allowed_args [:alfred, :server_name, :equipment, :programs]
  def new(args) do
    {final_args, _} = Keyword.split(args, @allowed_args)

    struct(State, final_args)
  end

  def refresh_programs(%State{} = s) do
    opts = sched_opts(s)

    %State{s | programs: Program.analyze_all(s.programs, opts)}
    |> refresh_playlist(opts)
  end

  def save_cmd(cmd, %State{} = s), do: struct(s, cmd_live: cmd)

  def save_programs(programs, %State{} = s), do: struct(s, programs: programs)

  def save_exec_result(%ExecResult{} = er, %State{} = s) do
    [exec_result: er, cmd_live: er.cmd] |> update(s)
  end

  def save_exec_result(term, %State{} = s) do
    case term do
      :keep -> [exec_result: term]
      _ -> [exec_result: term, cmd_live: :none]
    end
    |> update(s)
  end

  def save_ticket(ticket_rc, %State{} = s) do
    case ticket_rc do
      x when is_atom(x) -> %State{s | ticket: x}
      {:ok, x} -> %State{s | ticket: x}
      {:no_server, _} -> {:stop, :normal, s}
    end
  end

  def sched_opts(%State{} = s) do
    s
    |> Map.take([:alfred, :timezone])
    |> Enum.into([])
    |> Keyword.put(:datetime, Timex.now(s.timezone))
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

  def stop_notifies(%State{ticket: %Ticket{}} = s) do
    s.alfred.notify_unregister(s.ticket)

    save_ticket(:pause, s)
  end

  def stop_notifies(s), do: s

  def update_notify_at(s), do: struct(s, notify_at: Timex.now(s.timezone))

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  defp refresh_playlist(%State{programs: programs} = s, opts) do
    new_plist = Program.flatten(programs, opts) |> Playlist.refresh(s.playlist)

    [playlist: new_plist]
    |> then(fn fields -> struct(s, fields) end)
  end

  defp update(fields, s), do: struct(s, fields)
end
