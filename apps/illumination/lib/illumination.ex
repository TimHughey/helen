defmodule Illumination do
  require Logger

  defmacro __using__(use_opts) do
    quote location: :keep do
      def child_spec(start_args) do
        module = unquote(__CALLER__.module)
        use_opts = unquote(use_opts)
        {child_args, use_rest} = Keyword.split(use_opts, [:restart, :shutdown])

        all_args = [use_opts: use_rest, module: module, start_args: start_args]

        Supervisor.child_spec({Illumination.Server, all_args}, [id: module] ++ child_args)
      end
    end
  end
end
