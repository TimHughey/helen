defmodule Farm.Womb.Heater do
  use Rena,
    name: "womb heater",
    equipment: "womb heater power",
    sensor_group: [
      names: ["womb 1", "womb 2", "womb 3", "womb 4"],
      range: [high: 80.3, low: 78.7, unit: :temp_f],
      valid_when: [valid: 3, total: 3]
    ]
end
