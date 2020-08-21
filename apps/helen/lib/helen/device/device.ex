defmodule Helen.Device do
  @moduledoc """
  Abstraction to find the module for a device
  """

  def find_device_module(name) do
    for mod <- [PulseWidth, Switch, Sensor], reduce: nil do
      acc when is_nil(acc) ->
        # if apply(mod, :exists?, [name]), do: mod, else: nil

        if mod.exists?(name), do: mod, else: nil

      acc ->
        acc
    end
  end
end
