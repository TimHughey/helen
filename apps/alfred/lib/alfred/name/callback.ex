defmodule Alfred.Name.Callback do
  @moduledoc false

  def invoke(%{callbacks: callbacks} = name_info, invoke_args, action) do
    callback = Map.get(callbacks, action)

    case {callback, action} do
      # NOTE: execute or status are handled locally by Alfred
      {_, :execute} -> Alfred.Execute.execute_now(name_info, invoke_args)
      {_, :status} -> Alfred.Status.status_now(name_info, invoke_args)
      # NOTE: :execute_cmd and :status_lookup are handled by the using module
      {{module, 2}, :execute_cmd} -> apply(module, :execute_cmd, invoke_args)
      {{module, 2}, :status_lookup} -> apply(module, :status_lookup, invoke_args)
      {pid, action} when is_pid(pid) -> call(pid, action, invoke_args)
    end
  end

  def call(pid, action, invoke_args) do
    GenServer.call(pid, {action, invoke_args})
  end
end
