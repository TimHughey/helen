defmodule Rena.HoldCmd.State do
  alias __MODULE__

  alias Alfred.{ExecCmd, ExecResult}
  alias Alfred.Notify.Ticket

  defstruct alfred: Alfred,
            server_name: nil,
            equipment: "unknown",
            known_name: "default name",
            hold_cmd: %ExecCmd{cmd: "off", cmd_opts: [notify_when_released: true]},
            last_exec: :none,
            last_notify_at: nil

  @type hold_cmd() :: %ExecCmd{} | nil
  @type last_exec() :: :none | :failed | DateTime.t() | ExecCmd.t()
  @type t :: %State{
          alfred: module(),
          server_name: atom(),
          equipment: String.t() | Ticket.t(),
          known_name: String.t(),
          hold_cmd: hold_cmd(),
          last_exec: last_exec()
        }

  def new(args) do
    struct(State, args)
  end

  def save_equipment(%State{} = s, %Ticket{} = ticket), do: %State{s | equipment: ticket}

  # (1 of 2) handle pipelining
  def update_last_exec(what, %State{} = s), do: update_last_exec(s, what)

  # (2 of 2) handle pipelining
  def update_last_exec(%State{} = s, what) do
    case what do
      %DateTime{} = at -> %State{s | last_exec: at}
      %ExecResult{} = er -> %State{s | last_exec: er}
      :failed -> %State{s | last_exec: :failed}
      _ -> s
    end
  end

  def update_last_notify_at(%State{} = s), do: %State{s | last_notify_at: DateTime.utc_now()}
end
