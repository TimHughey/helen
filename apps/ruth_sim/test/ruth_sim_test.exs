defmodule RuthSimTest do
  use ExUnit.Case

  test "can RuthSim get the default device for PulseWidth devices" do
    ctx = %{type: "pwm"} |> RuthSim.default_device()
    default_device = get_in(ctx, [:default_device])
    assert is_binary(default_device)
  end
end
