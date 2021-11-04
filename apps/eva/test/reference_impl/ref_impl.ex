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

      if Alfred.available?(relay),
        do: Sally.device_add_alias(name: relay, device: "ds.29241708000000", pio: num),
        else: nil

      if Alfred.available?(i2c),
        do: Sally.device_add_alias(name: i2c, device: "i2c.30aea423a210.mcp23008:20", pio: num),
        else: nil

      :ok
    end

    Sally.device_add_alias(name: "led", device: "pwm.30aea423a210", pio: 0)
    Sally.device_add_alias(name: "pwm1", device: "pwm.30aea423a210", pio: 1)
    Sally.device_add_alias(name: "pwm2", device: "pwm.30aea423a210", pio: 2)
    Sally.device_add_alias(name: "pwm3", device: "pwm.30aea423a210", pio: 3)

    Sally.device_add_alias(name: "sht31", device: "i2c.30aea423a210.sht31:44", pio: 0)
    Sally.device_add_alias(name: "pcb", device: "ds.28ff280b6e1801", pio: 0)
    Sally.device_add_alias(name: "black temp", device: "ds.28ff9ace011703")
    Sally.device_add_alias(name: "green temp", device: "ds28ff88d4011703")

    :ok
  end
end
