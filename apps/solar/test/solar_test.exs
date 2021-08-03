defmodule SolarTest do
  use ExUnit.Case
  doctest Solar

  test "greets the world" do
    assert Solar.hello() == :world
  end
end
