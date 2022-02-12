defmodule Carol.TestAid do
  @doc false

  defmacro __using__(use_opts) do
    quote bind_quoted: [use_opts: use_opts] do
      def episodes_add(ctx), do: Carol.EpisodeAid.add(ctx)
      def init_add(ctx), do: Carol.InitAid.add(ctx)
      def opts_add(ctx), do: Carol.OptsAid.add(ctx)
      def start_args_add(ctx), do: Carol.StartArgsAid.add(ctx)
      def state_add(ctx), do: Carol.StateAid.add(ctx)
    end
  end
end
