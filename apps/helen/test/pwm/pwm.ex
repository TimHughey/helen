defmodule PulseWidthTest do
  @moduledoc false

  use Timex
  use ExUnit.Case

  test "can determine if a device exists?" do
    assert PulseWidth.exists?("front leds evergreen")
  end
end
