defmodule Eva.RefImpl.AutoOff do
  alias __MODULE__
  use Eva, name: AutoOff, id: AutoOff, restart: :permanent, shutdown: 1000
end

defmodule Eva.RefImpl.RuthLED do
  alias __MODULE__

  use Eva, name: RuthLED, id: RuthLED, restart: :permanent, shutdown: 1000
end

defmodule Eva.RefImpl.ManualTest do
  def setup do
    for num <- 0..7 do
      relay = "relay#{num}"
      i2c = "i2c#{num}"

      if Alfred.available?(relay), do: Sally.make_alias(relay, "ds29241708000000", num), else: nil
      if Alfred.available?(i2c), do: Sally.make_alias(i2c, "i2c30aea423a210.mcp23008:20", num), else: nil

      :ok
    end

    Sally.make_alias("led", "pwm30aea423a210", 0)
    Sally.make_alias("pwm1", "pwm30aea423a210", 1)
    Sally.make_alias("pwm2", "pwm30aea423a210", 2)
    Sally.make_alias("pwm3", "pwm30aea423a210", 3)

    Sally.make_alias("sht31", "i2c30aea423a210.sht31:44", 0)
    Sally.make_alias("pcb", "ds28ff280b6e1801", 0)
    Sally.make_alias("black temp", "ds28ff9ace011703", 0)
    Sally.make_alias("green temp", "ds28ff88d4011703", 0)

    :ok
  end
end
