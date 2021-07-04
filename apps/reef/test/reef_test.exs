defmodule ReefTest do
  use ExUnit.Case
  doctest Reef

  test "greets the world" do
    assert Reef.hello() == :world
  end
end
