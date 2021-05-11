defmodule DevicesTest do
  use ExUnit.Case
  doctest Devices

  test "greets the world" do
    assert Devices.hello() == :world
  end
end
