defmodule Alfred.TestAid do
  @moduledoc """
  `Sally` test context setup callbacks

  `Sally.TestAid` provides a variety of callbacks for convenient access to
  supporting functionality for setting up the test context.
  """

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Alfred.TestAid

      def new_dev_alias(type, opts), do: Alfred.NamesAid.new_dev_alias(type, opts)
      def equipment_add(ctx), do: Alfred.NamesAid.equipment_add(ctx)
      def memo_add(ctx), do: Alfred.NotifyAid.memo_add(ctx)
      def name_add(ctx), do: Alfred.NamesAid.name_add(ctx)
      def nofi_add(ctx), do: Alfred.NofiConsumer.nofi_add(ctx)
      def parts_add(ctx), do: Alfred.NamesAid.parts_add(ctx)
      def parts_auto_add(ctx), do: Alfred.NamesAid.parts_auto_add(ctx)
      def sensor_add(ctx), do: Alfred.NamesAid.sensor_add(ctx)
      def sensors_add(ctx), do: Alfred.NamesAid.sensors_add(ctx)
    end
  end

  @type test_ctx() :: map()
  @callback new_dev_alias(atom, list) :: Alfred.DevAlias.t()
  @callback equipment_add(test_ctx()) :: map()
  @callback memo_add(test_ctx) :: map()
  @callback nofi_add(test_ctx) :: map()
  @callback name_add(test_ctx) :: map()
  @callback parts_add(test_ctx) :: map()
  @callback parts_auto_add(test_ctx) :: map()
  @callback sensor_add(test_ctx()) :: map()
  @callback sensors_add(test_ctx()) :: map()
end
