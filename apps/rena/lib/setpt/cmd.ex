defmodule Rena.SetPt.Cmd do
  alias Rena.Sensor.Result

  def effectuate(%{action: :no_change}, _opts), do: :no_change

  def effectuate(%{action: action} = make_result, opts) do
    execute(make_result, opts) |> tap(fn x -> log_execute_result(x, action, opts) end)
  end

  def effectuate(error, opts) do
    case error do
      {:datapoint_error = x, _} -> Betty.app_error(opts, [{x, true}])
      {:equipment_error = x, %{name: name}} -> Betty.app_error(opts, [{x, true} | [name: name]])
    end

    :failed
  end

  def execute(%{equipment: equipment, next_cmd: next_cmd}, opts) do
    alfred = opts[:alfred] || Alfred

    cmd_args = [equipment: equipment, cmd: next_cmd]

    alfred.execute({cmd_args, notify: true})
  end

  @good [:ok, :busy]
  def log_execute_result(%{rc: rc, name: name}, action, opts) do
    tags = [equipment: name]

    if rc in @good do
      Betty.runtime_metric(opts, tags, [{action, true}])
    else
      Betty.app_error(opts, [{:cmd_fail, true} | tags])
    end
  end

  def put(what, key, acc), do: {:cont, Map.put(acc, key, what)}
  def put_ok(acc, key), do: {:cont, Map.put(acc, key, :ok)}

  def put_status(status, acc) do
    case status do
      %{rc: rc, story: %{cmd: cmd}} -> %{rc: rc, cmd: cmd}
      %{rc: rc} -> %{rc: rc}
    end
    |> Map.put(:status, status)
    |> then(fn merge -> {:cont, Map.merge(acc, merge)} end)
  end

  def activate(acc), do: {:cont, Map.merge(acc, %{next_cmd: "on", action: :activate})}
  def deactivate(acc), do: {:cont, Map.merge(acc, %{next_cmd: "off", action: :deactivate})}
  def no_change(acc), do: {:cont, Map.merge(acc, %{next_cmd: acc.cmd, action: :no_change})}

  @result_parts [:gt_high, :lt_low, :lt_mid, :total, :valid]
  def make(name, %Result{} = result, opts \\ []) do
    alfred = opts[:alfred] || Alfred

    # active_cmd = "on"
    # inactive_cmd = "off"

    base = %{equipment: name, result: result}
    result_parts = Map.take(result, @result_parts)
    initial_acc = Map.merge(base, result_parts)
    steps = [:datapoints, :status, :good, :want_cmd, :action, :default]

    Enum.reduce_while(steps, initial_acc, fn
      :datapoints = key, %{valid: x, total: y} = acc when x >= 3 and y >= 3 -> put_ok(acc, key)
      :datapoints, acc -> {:halt, {:datapoint_error, acc.result}}
      :status, acc -> alfred.status(name) |> put_status(acc)
      :good, %{rc: :ok} = acc -> {:cont, acc}
      :good, %{rc: :busy} = acc -> no_change(acc)
      :good, %{rc: _} = acc -> {:halt, {:equipment_error, acc.status}}
      :want_cmd, %{cmd: "on", gt_high: x} = acc when x >= 1 -> deactivate(acc)
      :want_cmd, %{cmd: "off", lt_low: x} = acc when x >= 1 -> activate(acc)
      :want_cmd, %{cmd: "off", lt_mid: x} = acc when x >= 2 -> activate(acc)
      :want_cmd, acc -> no_change(acc)
      :action, %{next_cmd: _, action: _} = acc -> {:halt, acc}
      _, acc -> {:cont, acc}
    end)
  end
end
