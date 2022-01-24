defmodule Sally.DeviceAidTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_device_aid: true

  setup [:host_add, :device_add]

  describe "DeviceAid.add/1" do
    @tag host_add: [], device_add: []
    test "inserts a new Device with defaults", ctx do
      assert %{device: %Sally.Device{family: "ds", mutable: false}} = ctx
    end

    @tag host_add: []
    test "does nothing when :device_add not present in context", ctx do
      refute is_map_key(ctx, :device)
    end

    @tag host_add: [], device_add: [auto: :mcp23008]
    test "inserts a mcp23008 device", ctx do
      assert %{device: %Sally.Device{family: "i2c", mutable: true}} = ctx
    end

    @tag host_add: [], device_add: [auto: :pwm]
    test "inserts a pwm device", ctx do
      assert %{device: %Sally.Device{family: "pwm", mutable: true}} = ctx
    end
  end
end
