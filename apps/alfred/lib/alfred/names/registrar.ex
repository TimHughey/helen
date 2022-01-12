# defmodule Alfred.Names.Registrar do
#   use Agent
#
#   @registry Alfred.Name.Registry
#
#   defmacrop format_exception(kind, reason) do
#     quote do
#       ["\n", Exception.format(unquote(kind), unquote(reason), __STACKTRACE__)] |> IO.puts()
#
#       {:failed, {unquote(kind), unquote(reason)}}
#     end
#   end
#
#   def start_link(opts) do
#     opts = Keyword.put_new(opts, :name, __MODULE__)
#     Agent.start_link(fn -> :ok end, opts)
#   end
#
#   def start_agent(opts) do
#     Agent.get(__MODULE__, fn _state -> try_start_agent(opts) end)
#   end
#
#   def stop_agent(name, pid) do
#     Agent.get(__MODULE__, fn _state ->
#       :ok = Registry.unregister(@registry, name)
#       Agent.stop(pid, :normal)
#     end)
#   end
#
#   ## PRIVATE
#   ## PRIVATE
#   ## PRIVATE
#
#   # NOTE: it appears try/catch blocks aren't available within anonymous functions
#   defp try_start_agent(opts) do
#     Alfred.Names.Name.start_link(opts)
#   catch
#     kind, reason -> format_exception(kind, reason)
#   end
# end
