defmodule Sally.DeviceAidTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag sally: true, sally_device_aid: true

  alias Sally.{Device, DeviceAid, HostAid}

  setup [:host_add, :host_setup, :device_add]

  describe "DeviceAid.add/1" do
    @tag host_add: [], host_setup: [], device_add: []
    test "inserts a new Device with defaults", ctx do
      Should.Be.Map.with_key(ctx, :device)

      want_kv = [family: "ds", mutable: false]
      Should.Be.Struct.with_all_key_value(ctx.device, Device, want_kv)
    end

    @tag host_add: []
    test "does nothing when :device_add not present in context", ctx do
      Should.Be.Map.without_key(ctx, :device)
    end

    @tag host_add: [], host_setup: [], device_add: [auto: :mcp23008]
    test "inserts a mcp23008 device", ctx do
      Should.Be.Map.with_key(ctx, :device)
      want_kv = [family: "i2c", mutable: true]
      Should.Be.Struct.with_all_key_value(ctx.device, Device, want_kv)
    end

    @tag host_add: [], host_setup: [], device_add: [auto: :pwm]
    test "inserts a pwm device", ctx do
      want_kv = [family: "pwm", mutable: true]

      ctx
      |> Should.Be.Map.with_key(:device)
      |> Should.Be.Schema.with_all_key_value(Device, want_kv)
    end
  end

  def device_add(ctx), do: DeviceAid.add(ctx)
  def host_add(ctx), do: HostAid.add(ctx)
  def host_setup(ctx), do: HostAid.setup(ctx)
end
