defmodule Rena.HoldCmd.Cmd do
  require Logger

  alias Alfred.{ExecCmd, ExecResult}

  alias Alfred.Notify.Memo

  def hold(%Memo{} = memo, %ExecCmd{cmd: want_cmd} = hold_cmd, opts) do
    alfred = opts[:alfred]

    ec = %ExecCmd{hold_cmd | name: memo.name}

    # NOTE: Alfred.execute/2, by default, only acts when
    # current cmd != requested cmd
    case alfred.execute(ec, opts) do
      %ExecResult{rc: :ok, cmd: ^want_cmd} -> {:no_change, want_cmd}
      %ExecResult{rc: :pending, cmd: ^want_cmd} -> {:pending, want_cmd}
      er -> ExecResult.log_failure(er, opts)
    end
  end
end
