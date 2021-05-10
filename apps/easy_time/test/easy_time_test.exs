defmodule EasyTimeTest do
  use ExUnit.Case
  doctest EasyTime

  test "greets the world" do
    assert EasyTime.hello() == :world
  end
end
