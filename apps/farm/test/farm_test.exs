defmodule FarmTest do
  use ExUnit.Case, async: true
  use Carol.AssertAid, module: Farm
  import Should, only: [assert_started: 2]

  describe "Womb.Farm.Heater" do
    test "starts" do
      assert_started(Farm.Womb.Heater, attempts: 10)
    end
  end
end
