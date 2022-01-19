defmodule Rena.SetPt.Cmd do
  alias Rena.Sensor.Result

  def effectuate(make_result, opts) do
    case make_result do
      {action, cmd_args} when action in [:activate, :deactivate] ->
        execute(cmd_args, opts) |> log_execute_result(action, opts)

      {:datapoint_error = x, _} ->
        Betty.app_error(opts, [{x, true}])
        :failed

      {:error, reason} ->
        Betty.app_error(opts, [{reason, true}])
        :failed

      {:equipment_error, %{name: name, rc: {:ttl_expired, ms}}} ->
        Betty.app_error(opts, equipment: name, equipment_error: "ttl_expired #{ms}ms")
        :failed

      {:equipment_error, %{name: name, rc: {:orphaned, ms}}} ->
        Betty.app_error(opts, equipment: name, equipment_error: "orphaned #{ms}ms")
        :failed

      {:equipment_error, %{name: name, rc: rc}} ->
        Betty.app_error(opts, equipment: name, equipment_error: rc)
        :failed

      {:no_change, _status} ->
        :no_change
    end
  end

  def execute(cmd_args, opts) do
    alfred = opts[:alfred] || Alfred

    cmd_args = Enum.into(cmd_args, [])

    case alfred.execute({cmd_args, []}) do
      %Alfred.Execute{rc: rc} = execute when rc in [:ok, :pending] -> {:ok, execute}
      %Alfred.Execute{} = execute -> {:failed, execute}
    end
  end

  def log_execute_result({rc, %{name: name} = execute}, action, opts) do
    tags = [equipment: name]

    # always log that an action was performed (even if it failed)
    Betty.runtime_metric(opts, tags, [{action, true}])

    if rc == :failed do
      Betty.app_error(opts, [{:cmd_fail, true} | tags])
    end

    # pass through the execute result
    execute
  end

  def make(name, %Result{} = result, opts \\ []) do
    alfred = opts[:alfred] || Alfred
    cmd_args = %{name: name, cmd_opts: [notify_when_released: true]}

    active_cmd_args = opts[:active_cmd] || Map.put(cmd_args, :cmd, "on")
    inactive_cmd_args = opts[:inactive_cmd] || Map.put(cmd_args, :cmd, "off")

    with {:datapoints, true} <- sufficient_datapoints?(result),
         {:active_cmd, active_cmd_args} <- {:active_cmd, active_cmd_args},
         {:inactive_cmd, inactive_cmd_args} <- {:inactive_cmd, inactive_cmd_args},
         %Alfred.Status{rc: :ok} = full_status <- alfred.status(name) do
      status = simple_status(full_status, active_cmd_args)

      activate? = status == :inactive and should_be_active?(result)
      deactivate? = status == :active and should_be_inactive?(result)

      cond do
        activate? -> {:activate, active_cmd_args}
        deactivate? -> {:deactivate, inactive_cmd_args}
        true -> {:no_change, status}
      end
    else
      {:datapoints, false} -> {:datapoint_error, result}
      {:active_cmd, _} -> {:error, :invalid_active_cmd}
      {:inactive_cmd, _} -> {:error, :invalid_inactive_cmd}
      %Alfred.Status{} = status -> {:equipment_error, status}
    end
  end

  # safety first is the priority so we will always error on the side of inactive
  #
  # safety checks (e.g. sufficient valid data points) are performed prior to
  # determining active vs inactive
  #
  # should_be_active? and should_be_inactive? are closely related however do not
  # mirror each other exactly
  #
  # system is inactive when:
  #  1. one or more sensors are gt_high (prcent over temp)
  #
  # system is active when:
  #  1. one or more sensors are lt_low (prevent low temperature)
  #  2. two or more sensors are lt_mid (prevent temperature from dropping below low)

  defp should_be_active?(result) do
    case result do
      %Result{gt_high: x} when x >= 1 -> false
      %Result{lt_low: x} when x >= 1 -> true
      %Result{lt_mid: x} when x >= 2 -> true
      _ -> false
    end
  end

  defp should_be_inactive?(result) do
    case result do
      %Result{gt_high: x} when x >= 1 -> true
      _ -> false
    end
  end

  defp simple_status(status, cmd_args) when is_list(cmd_args) do
    simple_status(status, Enum.into(cmd_args, %{}))
  end

  defp simple_status(%Alfred.Status{detail: %{cmd: have}}, %{cmd: want}) when have == want, do: :active
  defp simple_status(%Alfred.Status{detail: %{cmd: have}}, %{cmd: want}) when have != want, do: :inactive

  defp sufficient_datapoints?(%Result{valid: x, total: y}) when x >= 3 and y >= 3, do: {:datapoints, true}
  defp sufficient_datapoints?(%Result{}), do: {:datapoints, false}
end
