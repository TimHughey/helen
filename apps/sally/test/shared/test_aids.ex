defmodule Sally.TestAid do
  @moduledoc """
  `Sally` test context setup callbacks

  `Sally.TestAid` provides a variety of callbacks for convenient access to
  supporting functionality for setting up the test context.
  """

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Sally.TestAid

      def command_add(ctx), do: Sally.CommandAid.add(ctx)
      def datapoint_add(ctx), do: Sally.DatapointAid.add(ctx)
      def devalias_add(ctx), do: Sally.DevAliasAid.add(ctx)
      def devalias_just_saw(ctx), do: Sally.DevAliasAid.just_saw(ctx)
      def device_add(ctx), do: Sally.DeviceAid.add(ctx)
      def dispatch_add(ctx), do: Sally.DispatchAid.add(ctx)
      def host_add(ctx), do: Sally.HostAid.add(ctx)
      def host_setup(ctx), do: Sally.HostAid.setup(ctx)
    end
  end

  @type test_ctx() :: map()
  @callback command_add(test_ctx()) :: map()
  @callback datapoint_add(test_ctx()) :: map()
  @callback devalias_add(test_ctx()) :: map()
  @callback devalias_just_saw(test_ctx()) :: map()
  @callback dispatch_add(test_ctx()) :: map()
  @callback host_add(test_ctx()) :: map()
  @callback host_setup(test_ctx()) :: map()
end
