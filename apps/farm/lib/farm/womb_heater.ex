defmodule Farm.Womb.Heater do
  use Rena,
    name: "womb heater",
    equipment: "womb heater power",
    sensor_group: [
      names: ["womb 1", "womb 2", "womb 3", "womb 4"],
      range: [high: 80.0, low: 78.0, unit: :temp_f],
      # NOTE: Rena provides [lower: [gt_high: 1], raise: [lt_low: 1]] by default
      adjust_when: [lower: [gt_high: 1, gt_mid: 1, lt_mid: 1], raise: [lt_low: 1]],
      valid_when: [valid: 3, total: 3]
    ]
end
