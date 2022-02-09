defmodule Sally.DeviceTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_device: true

  setup [:host_add, :device_add, :dev_alias_add]

  describe "Sally.Device.find/1" do
    @tag host_add: [], device_add: [auto: :pwm]
    test "finds devices of a specific family", ctx do
      assert %{device: %{id: id}} = ctx

      family = "pwm"
      devices = Sally.Device.find(family: family)

      assert Enum.count(devices) >= 1
      assert Enum.all?(devices, &match?(%{family: ^family}, &1))
      assert %{id: ^id} = Enum.find(devices, &match?(%{id: ^id}, &1))
    end

    # NOTE: ensure there is at least one mutable device
    @tag dev_alias_add: [auto: :pwm]
    test "finds mutable devices", ctx do
      %{device: %{id: id}} = ctx

      mutable? = true
      devices = Sally.Device.find(mutable: mutable?)

      assert Enum.count(devices) >= 1
      assert Enum.all?(devices, &match?(%{mutable: ^mutable?}, &1))
      assert %{id: ^id} = Enum.find(devices, &match?(%{id: ^id}, &1))
    end

    # NOTE: ensure there is at least one immutable device
    @tag dev_alias_add: [auto: :ds]
    test "finds immutable devices", ctx do
      %{device: %{id: id}} = ctx

      mutable? = false
      devices = Sally.Device.find(mutable: mutable?)

      assert Enum.count(devices) >= 1
      assert Enum.all?(devices, &match?(%{mutable: ^mutable?}, &1))
      assert %{id: ^id} = Enum.find(devices, &match?(%{id: ^id}, &1))
    end
  end
end
