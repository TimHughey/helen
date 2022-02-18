defmodule Carol.TestAid do
  @doc false

  defmacro __using__(_use_opts) do
    quote do
      def episodes_add(ctx), do: Carol.EpisodeAid.add(ctx)
      def init_add(ctx), do: Carol.InitAid.add(ctx)
      def start_args_add(ctx), do: Carol.StartArgsAid.add(ctx)
    end
  end
end
