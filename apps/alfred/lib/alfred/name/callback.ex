defmodule Alfred.Name.Callback do
  @moduledoc false

  def invoke(%{callbacks: callbacks} = name_info, invoke_args, action) do
    callback = Map.get(callbacks, action)

    case {callback, action} do
      # NOTE: execute or status are handled locally by Alfred
      {_, :execute} -> Alfred.Execute.execute_now(name_info, invoke_args)
      {_, :status} -> Alfred.Status.status_now(name_info, invoke_args)
      # NOTE: :execute_cmd is hand;ed by the implementing module or server
      {{module, 2}, :execute_cmd} -> apply(module, :execute_cmd, invoke_args)
      {pid, :execute_cmd} when is_pid(pid) -> GenServer.call(pid, {:execute_cmd, name_info, invoke_args})
      # NOTE: :status_lookup is hand;ed by the implementing module or server
      {{module, 2}, :status_lookup} -> apply(module, :status_lookup, invoke_args)
      {pid, :status_lookup} when is_pid(pid) -> GenServer.call(pid, {:status_lookup, name_info, invoke_args})
    end
  end
end
