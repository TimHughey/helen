defmodule FarmTest do
  use ExUnit.Case, async: true
  import Should, only: [assert_started: 2]

  describe "Farm.Womb.Heater" do
    test "starts" do
      assert_started(Farm.Womb.Heater, attempts: 10)
    end
  end

  describe "Farm.Womb.Circulation" do
    test "starts" do
      assert_started(Farm.WombCirculation, attempts: 10)
    end
  end
end
