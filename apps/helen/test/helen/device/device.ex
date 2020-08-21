defmodule HelenDeviceTest do
  @moduledoc false

  use Timex
  use ExUnit.Case

  alias Helen

  test "can find module for a device?" do
    assert Helen.Device.find_device_module("front leds evergreen")
  end

  test "can find a switch" do
    assert Helen.Device.find_device_module("irrigation garden")
  end

  test "can find a sensor" do
    assert Helen.Device.find_device_module("display_tank")
  end
end
