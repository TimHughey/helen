defmodule Rena.HoldCmd.State do
  alias __MODULE__

  alias Alfred.{ExecCmd, ExecResult}
  alias Alfred.Notify.Ticket

  defstruct alfred: Alfred,
            server_name: nil,
            equipment: "unknown",
            ticket: :none,
            known_name: "default name",
            hold_cmd: %ExecCmd{cmd: "off", cmd_opts: [notify_when_released: true]},
            last_exec: :none,
            last_notify_at: :none

  @type hold_cmd() :: %ExecCmd{} | nil
  @type last_exec() :: :none | :failed | {:no_change, String.t()} | {:pending, String.t()}
  @type ticket() :: :none | :paused | Ticket.t()
  @type t :: %State{
          alfred: module(),
          server_name: atom(),
          equipment: String.t() | Ticket.t(),
          ticket: ticket(),
          known_name: String.t(),
          hold_cmd: hold_cmd(),
          last_exec: last_exec()
        }

  def new(args) do
    struct(State, args) |> finalize_hold_cmd()
  end

  def pause_notifies(%State{ticket: ticket} = s) do
    case ticket do
      %Ticket{} = x ->
        s.alfred.notify_unregister(x)
        save_ticket(:paused, s)

      x when x in [:none, :paused] ->
        s
    end
  end

  def save_ticket(ticket_rc, %State{} = s) do
    case ticket_rc do
      x when is_atom(x) -> %State{s | ticket: x}
      {:ok, x} -> %State{s | ticket: x}
      {:no_server, _} -> {:stop, :normal, s}
    end
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

  # (1 of 2) handle pipelining
  def update_last_exec(what, %State{} = s), do: update_last_exec(s, what)

  # (2 of 2) handle pipelining
  def update_last_exec(%State{} = s, what) do
    case what do
      x when is_tuple(x) -> x
      x when is_atom(x) -> x
      %DateTime{} = at -> at
      %ExecResult{} = er -> er
    end
    |> then(fn result -> struct(s, last_exec: result) end)
  end

  def update_last_notify_at(%State{} = s), do: %State{s | last_notify_at: DateTime.utc_now()}

  defp finalize_hold_cmd(%State{hold_cmd: hold_cmd} = s) do
    cmd_opts = Keyword.put(hold_cmd.cmd_opts, :notify_when_released, true)

    %State{s | hold_cmd: %ExecCmd{hold_cmd | name: s.equipment, cmd_opts: cmd_opts}}
  end
end
