defmodule Lights.Devices.Impl do
  @moduledoc false

  defmacro __using__(_opts) do
    if Mix.env() in [:dev, :test] do
      quote do
        def exists?(name, _opts \\ []) do
          name in [
            "test device",
            "indoor garden alpha",
            "front leds porch",
            "front leds red maple",
            "front leds evergreen"
          ]
        end
      end
    else
      quote do
        def exists?(name, opts \\ []) do
          mods = [PulseWidth, Switch]

          node = get_in(opts, [:node]) || default_node()

          for mod when is_atom(mod) <- mods, reduce: false do
            true -> true
            {:badrpc, _x} -> false
            false -> apply_or_rpc(node, mod, :exists?, name)
            _x -> false
          end
        end

        def apply_or_rpc(node, mod, func, args) when node == node() do
          import List, only: [flatten: 1]

          apply(mod, func, flatten([args]))
        end

        def apply_or_rpc(node, mod, func, args) do
          import List, only: [flatten: 1]

          :rpc.call(node, mod, func, flatten([args]))
        end
      end
    end
  end
end
