defmodule Carol do
  require Logger

  defmacro __using__(use_opts) do
    quote location: :keep do
      def child_spec(start_args) do
        module = unquote(__CALLER__.module)
        use_opts = unquote(use_opts)
        {child_args, use_rest} = Keyword.split(use_opts, [:restart, :shutdown])

        all_args = [use_opts: use_rest, module: module, start_args: start_args]

        Supervisor.child_spec({Carol.Server, all_args}, [id: module] ++ child_args)
      end

      def info do
        :sys.get_state(unquote(__CALLER__.module)).result
      end

      def restart do
        GenServer.call(unquote(__CALLER__.module), :restart)
      end
    end
  end
end
