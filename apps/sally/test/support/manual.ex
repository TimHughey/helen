defmodule Sally.Test.Manual do
  def clean_up_db do
  end

  def make_aliases do
    test_with_devs = [
      [name: "pcb", ident: "ds.28ff280b6e1801", description: "test-with-devs pcb ds1820"],
      [name: "green temp", ident: "ds.28ff88d4011703", description: "green ds1820 probe"],
      [name: "black temp", ident: "ds.28ff9ace011703", description: "black ds1820 probe"],
      [name: "relay0", ident: "ds.29241708000000", description: "io relay board pin 0"],
      [name: "led", ident: "pwm.30aea423a210", pio: 0, description: "test-with-devs status led"]
    ]

    for opts <- test_with_devs do
      Sally.device_add_alias(opts)
    end
  end
end
