defmodule Sally.TestAid do
  @moduledoc """
  `Sally` test context setup callbacks

  `Sally.TestAid` provides a variety of callbacks for convenient access to
  supporting functionality for setting up the test context.
  """

  defmacro __using__(_) do
    quote location: :keep do
      use Should
      @behaviour Sally.TestAid

      def devalias_add(ctx), do: Sally.DevAliasAid.add(ctx)
      def dev_alias_add(ctx), do: Sally.DevAliasAid.add(ctx)
      def device_add(ctx), do: Sally.DeviceAid.add(ctx)
      def dispatch_add(ctx), do: Sally.DispatchAid.add(ctx)
      def host_add(ctx), do: Sally.HostAid.add(ctx)
    end
  end

  @type test_ctx() :: map()
  @callback devalias_add(test_ctx()) :: map()
  @callback dev_alias_add(test_ctx()) :: map()
  @callback dispatch_add(test_ctx()) :: map()
  @callback host_add(test_ctx()) :: map()
end
