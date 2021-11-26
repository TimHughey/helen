defmodule Rena.TestAids do
  defmacro __using__(_) do
    quote location: :keep do
      alias Rena.StartArgsAid

      require StartArgsAid

      def start_args_add(ctx), do: StartArgsAid.add(ctx)
    end
  end
end
