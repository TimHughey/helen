defmodule RenaTest do
  use ExUnit.Case
  doctest Rena

  test "greets the world" do
    assert Rena.hello() == :world
  end
end
