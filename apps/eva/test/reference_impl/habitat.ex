defmodule Eva.Habitat do
  alias __MODULE__
  use Eva, name: Habitat, id: Habitat, restart: :permanent, shutdown: 1000
end

defmodule Eva.RefImpl.AutoOff do
  alias __MODULE__
  use Eva, name: AutoOff, id: AutoOff, restart: :permanent, shutdown: 1000
end

defmodule Eva.RefImpl.ManualTest do
  def setup do
    for num <- 0..7 do
      name = "relay#{num}"

      case Alfred.status(name) do
        {:failed, _} -> Sally.make_alias("relay#{num}", "ds29241708000000", num)
        _ -> nil
      end
    end

    for num <- 0..7 do
      name = "i2c#{num}"

      case Alfred.status(name) do
        {:failed, _} -> Sally.make_alias("i2c#{num}", "i2c30aea423a210.mcp23008:20", num)
        _ -> nil
      end
    end

    Sally.make_alias("sht31", "i2c30aea423a210.sht31:44", 0)
    Sally.make_alias("pcb", "ds28ff280b6e1801", 0)
    Sally.make_alias("black temp", "ds28ff9ace011703", 0)
    Sally.make_alias("green temp", "ds28ff88d4011703", 0)

    :ok
  end
end
