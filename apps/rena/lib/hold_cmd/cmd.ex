defmodule Rena.HoldCmd.Cmd do
  require Logger

  alias Alfred.{ExecCmd, ExecResult}
  alias Alfred.MutableStatus, as: MutStatus
  alias Alfred.Notify.Memo

  def align(%MutStatus{} = status, %ExecCmd{} = hold_cmd, opts) do
    alfred = opts[:alfred]

    %ExecCmd{hold_cmd | name: status.name}
    |> alfred.execute(opts)
  end

  def hold(%Memo{} = memo, %ExecCmd{cmd: want_cmd} = hold_cmd, opts) do
    alfred = opts[:alfred]

    status = alfred.status(memo.name)

    # NOTE: do nothing when pending to prevent spurious commands
    case status do
      %MutStatus{cmd: ^want_cmd} -> :no_change
      %MutStatus{pending?: true, cmd: ^want_cmd} -> :no_change
      %MutStatus{good?: true} -> align(status, hold_cmd, opts)
      %MutStatus{good?: false} -> status_failed(status, opts)
    end
    |> check_exec_result(opts)
  end

  defp check_exec_result(:no_change, _opts), do: :no_change

  defp check_exec_result(%ExecResult{} = er, _opts) do
    er
  end

  defp status_failed(%MutStatus{} = status, opts) do
    server_name = opts[:server_name]

    tags = [equipment: status.name, status_failed: true]
    Betty.app_error(server_name, tags)

    :status_error
  end
end
