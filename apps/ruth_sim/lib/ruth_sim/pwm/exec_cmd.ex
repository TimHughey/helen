defmodule PwmSim.ExecCmd do
  require Logger

  def inbound_cmd_msg(%{device: dev_name, host: msg_host, pio: pio} = cmd_msg) do
    alias PwmSim.Report

    with %PwmSim{host: h} = sim when msg_host == h <- PwmKeeper.load(dev_name),
         {:exec_cmd, exec_cmd} <- get_exec_cmd(cmd_msg),
         {:valid_exec_cmd, exec_cmd} <- validate_exec_cmd(exec_cmd) do
      # 1. the PwmSim has been found for the cmd msg
      # 2. retrieved the exec cmd
      # 3. validated the exec cmd
      # 4. hand-off to PwmSim to apply the exec cmd, returns the updated PwmSim
      PwmSim.apply_exec_cmd(sim, pio, exec_cmd)
      # 5. hand-off to Report to publish the required reply to an exec cmd.
      |> Report.publish(cmd_msg)
    else
      error -> ["\nexec_cmd failed:\n", inspect(error, pretty: true)] |> Logger.warn()
    end
  end

  defp get_exec_cmd(cmd_msg) do
    # cmd msgs must include :exec with a single exec cmd
    case cmd_msg do
      %{exec: [exec_cmd]} -> {:exec_cmd, exec_cmd}
      _ -> {:invalid_cmd_msg, %{}}
    end
  end

  defp validate_exec_cmd(exec_cmd) do
    # two flavors of exec cmds
    # 1. 'builtin' on and off
    # 2. custom where where :cmd and :type are required and other keys are passed through
    case exec_cmd do
      %{cmd: c} when c in ["on", "off"] -> {:valid_exec_cmd, %{cmd: c}}
      %{cmd: _, type: _} = ec -> {:valid_exec_cmd, ec}
      ec -> {:invalid_exec_cmd, ec}
    end
  end
end
