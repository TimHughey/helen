defmodule PulseWidthTest do
  @moduledoc false

  use Timex
  use ExUnit.Case

  test "can determine if a device exists?" do
    assert PulseWidth.exists?("front leds evergreen")
  end

  test "can PulseEWidth.duty/2 accept binary duty values?" do
    res = PulseWidth.duty("front leds evergreen", "0.75")

    assert is_tuple(res)
    assert {:pending, _} = res

    fail = PulseWidth.duty("front leds evergreen", "not a number")

    assert fail == :bad_value
  end
end
