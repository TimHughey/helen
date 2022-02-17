defmodule Rena.TestAid do
  @moduledoc false

  defmacro __using__(_use_opts) do
    quote do
      @behaviour unquote(__MODULE__)

      def init_add(ctx), do: Rena.InitArgsAid.add(ctx)
      def sensor_group_add(ctx), do: Rena.SensorGroupAid.add(ctx)
    end
  end

  @callback init_add(map) :: map
  @callback sensor_group_add(map) :: map
end
