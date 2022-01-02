defmodule Sally.DeviceTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_device: true

  setup_all do
    # always create and setup a host
    {:ok, %{host_add: [], host_setup: []}}
  end

  setup [:host_add, :host_setup, :device_add, :devalias_add, :devalias_just_saw]

  test "the truth will set you free" do
    assert true == true
  end
end
