defmodule RuthSimTest do
  use ExUnit.Case
  doctest RuthSim

  test "greets the world" do
    assert RuthSim.hello() == :world
  end
end
