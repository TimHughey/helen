a = %{
  "front leds evergreen" => "pwm/lab-ledge.pin:3",
  "front leds porch" => "pwm/lab-ledge.pin:1",
  "front red maple" => "pwm/lab-ledge.pin:2",
  "roost disco ball" => "pwm/roost-alpha.pin:1",
  "roost el wire" => "pwm/roost-alpha.pin:3",
  "roost el wire entry" => "pwm/roost-alpha.pin:2",
  "roost led forest" => "pwm/roost-beta.pin:2",
  "roost lights sound one" => "pwm/roost-gamma.pin:1",
  "roost lights sound three" => "pwm/roost-beta.pin:1",
  "test1" => "pwm/test-builder.pin:1",
  "tt1" => "pwm/test-builder.pin:2"
}

for {pwm_alias, device} <- a, do: PulseWidth.alias_create(device, device)
