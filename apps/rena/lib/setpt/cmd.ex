defmodule Rena.SetPt.Cmd do
  alias Alfred.{ExecCmd, ExecResult}
  alias Alfred.MutableStatus, as: MutStatus
  alias Rena.Sensor.Result

  def effectuate(make_result, opts) do
    case make_result do
      {action, %ExecCmd{} = ec} when action in [:activate, :deactivate] ->
        execute(ec, opts) |> log_execute_result(action, opts)

      {:datapoint_error = x, _} ->
        Betty.app_error(opts, [{x, true}])
        :failed

      {:error, reason} ->
        Betty.app_error(opts, [{reason, true}])
        :failed

      {:equipment_error, %MutStatus{name: name, ttl_expired?: true}} ->
        Betty.app_error(opts, equipment: name, equipment_error: "ttl_expired")
        :failed

      {:equipment_error, %MutStatus{name: name, error: error}} ->
        Betty.app_error(opts, equipment: name, equipment_error: error)
        :failed

      {:no_change, _status} ->
        :no_change
    end
  end

  def execute(%ExecCmd{} = ec, opts) do
    alfred = opts[:alfred] || Alfred

    case alfred.execute(ec) do
      %ExecResult{rc: rc} = exec_result when rc in [:ok, :pending] -> {:ok, exec_result}
      %ExecResult{} = exec_result -> {:failed, exec_result}
    end
  end

  def log_execute_result({rc, %ExecResult{} = er}, action, opts) when action in [:activate, :deactivate] do
    tags = [equipment: er.name]

    # always log that an action was performed (even if it failed)
    Betty.runtime_metric(opts, tags, [{action, true}])

    if rc == :failed do
      Betty.app_error(opts, tags ++ [cmd_fail: true])
    end

    # pass through the ExecResult
    er
  end

  def make(name, %Result{} = result, opts \\ []) do
    alfred = opts[:alfred] || Alfred
    cmd_opts = [notify_when_released: true]
    active_cmd_opt = opts[:active_cmd] || %ExecCmd{cmd: "on", cmd_opts: cmd_opts}
    inactive_cmd_opt = opts[:inactive_cmd] || %ExecCmd{cmd: "off", cmd_opts: cmd_opts}

    with {:result, true} <- {:result, sufficient_datapoints?(result)},
         {:active_cmd, %ExecCmd{} = active_cmd} <- {:active_cmd, active_cmd_opt},
         {:inactive_cmd, %ExecCmd{} = inactive_cmd} <- {:inactive_cmd, inactive_cmd_opt},
         %MutStatus{good?: true} = mut_status <- alfred.status(name) do
      status = simple_status(mut_status, active_cmd)

      activate? = status == :inactive and should_be_active?(result)
      deactivate? = status == :active and should_be_inactive?(result)

      cond do
        activate? -> {:activate, %ExecCmd{active_cmd | name: name}}
        deactivate? -> {:deactivate, %ExecCmd{inactive_cmd | name: name}}
        true -> {:no_change, status}
      end
    else
      {:result, false} -> {:datapoint_error, result}
      {:active_cmd, _} -> {:error, :invalid_active_cmd}
      {:inactive_cmd, _} -> {:error, :invalid_inactive_cmd}
      %MutStatus{} = x -> {:equipment_error, x}
    end
  end

  # the focus of deciding active vs inactive is safety first so the preference is
  # to error on the side of inactive.
  #
  # should_be_active? and should_be_inactive? are closely related however do not
  # mirror each other exactly  both functions implement safety vhecks.
  #
  # system is inactive when:
  #  1. one or more sensors are gt_high
  #  2. two or more esnsors are gt_mid (to prevent temperature overshoot)
  #  3. less than three available datapoints (ensure redundancy)
  #  4. less than three valid datapoints (ensure good data)
  #
  # system is active when:
  #  1. one or more sensors are lt_low (prevent low temperature)
  #  2. two or more sensors are lt_mid (prevent temperature from dropping below low)

  defp should_be_active?(result) do
    case result do
      %Result{total: x} when x < 3 -> false
      %Result{valid: x} when x < 3 -> false
      %Result{gt_high: x} when x > 0 -> false
      %Result{lt_low: x} when x > 0 -> true
      %Result{lt_mid: x} when x >= 2 -> true
      _ -> false
    end
  end

  defp should_be_inactive?(result) do
    case result do
      %Result{total: x} when x < 3 -> true
      %Result{valid: x} when x < 3 -> true
      %Result{gt_high: x} when x > 0 -> true
      %Result{gt_mid: x} when x >= 2 -> true
      _ -> false
    end
  end

  defp simple_status(%MutStatus{cmd: scmd}, %ExecCmd{cmd: acmd}) when scmd == acmd, do: :active
  defp simple_status(%MutStatus{}, %ExecCmd{}), do: :inactive

  defp sufficient_datapoints?(%Result{valid: x, total: y}) when x >= 3 and y >= 3, do: true
  defp sufficient_datapoints?(%Result{}), do: false

  # defp should_be_inactive?(%Result{invalid: x}) when x >= 2, do: true
  # defp should_be_inactive?(%Result{total: x}) when x < 3, do: true
  # defp should_be_inactive?(%Result{gt_high: x}) when x > 0, do: true
  # defp should_be_inactive?(%Result{gt_mid: x}) when x >= 2, do: true
  # defp should_be_inactive?(%Result{}), do: false
end
