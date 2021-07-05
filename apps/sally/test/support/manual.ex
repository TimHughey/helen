defmodule Sally.Test.Manual do
  def clean_up_db do
  end

  def make_aliases do
    [
      Sally.make_alias("pcb", "ds28ff280b6e1801", 0, description: "test-with-devs pcb ds1820"),
      Sally.make_alias("green temp", "ds28ff88d4011703", 0, description: "green ds1820 probe"),
      Sally.make_alias("black temp", "ds28ff9ace011703", 0, description: "black ds1820 probe"),
      Sally.make_alias("relay0", "ds29241708000000", 0, description: "io relay board pin 0"),
      Sally.make_alias("led", "pwm30aea423a210", 0, description: "test-with-devs status led")
    ]
  end
end
