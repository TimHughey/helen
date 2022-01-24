defmodule Sally.DeviceTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_device: true

  test "the truth will set you free" do
    assert true == true
  end
end
