defmodule Sally.TestAids do
  defmacro __using__(_) do
    quote location: :keep do
      alias Sally.CommandAid
      alias Sally.DatapointAid
      alias Sally.{DevAliasAid, DeviceAid}
      alias Sally.DispatchAid
      alias Sally.HostAid

      require CommandAid
      require DatapointAid
      require DevAliasAid
      require DeviceAid
      require DispatchAid
      require HostAid

      def command_add(ctx), do: CommandAid.add(ctx)
      def datapoint_add(ctx), do: DatapointAid.add(ctx)
      def devalias_add(ctx), do: DevAliasAid.add(ctx)
      def devalias_just_saw(ctx), do: DevAliasAid.just_saw(ctx)
      def device_add(ctx), do: DeviceAid.add(ctx)
      def dispatch_add(ctx), do: DispatchAid.add(ctx)
      def host_add(ctx), do: HostAid.add(ctx)
      def host_setup(ctx), do: HostAid.setup(ctx)
    end
  end
end
