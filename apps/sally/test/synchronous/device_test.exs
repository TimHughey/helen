defmodule Sally.Synchronous.DeviceTest do
  use ExUnit.Case
  use Sally.TestAid

  @moduletag sally: true, sally_synchronous_device: true

  setup [:host_add, :device_add, :dev_alias_add]

  describe "Sally.device_move_aliases/1" do
    @tag dev_alias_add: [auto: :mcp23008, count: 8]
    test "moves aliases from src to dest ident", ctx do
      %{host: host, device: %Sally.Device{ident: src_ident}} = ctx

      # create a second device to serve as the destination
      add_ctx = %{host: host, device_add: [auto: :mcp23008]}
      assert %{device: %Sally.Device{ident: dest_ident}} = Sally.DeviceAid.add(add_ctx)

      move_opts = [from: src_ident, to: dest_ident]

      assert {:ok, %Sally.Device{ident: moved_ident} = moved_device} = Sally.device_move_aliases(move_opts)

      # verify the two devices were indeed different
      assert src_ident != moved_ident

      all_equal =
        for %Sally.DevAlias{name: name} <- ctx.dev_alias,
            %Sally.DevAlias{name: moved_name} when moved_name == name <- moved_device.aliases do
          true
        end

      assert Enum.all?(all_equal, fn x -> x end)
    end

    @tag dev_alias_add: [auto: :mcp23008, count: 8]
    test "moves aliases to the latest device created", ctx do
      %{host: host, device: %Sally.Device{ident: src_ident}} = ctx

      # create a second device to serve as the destination
      add_ctx = %{host: host, device_add: [auto: :mcp23008]}
      assert %{device: %Sally.Device{}} = Sally.DeviceAid.add(add_ctx)

      move_opts = [from: src_ident, to: :latest, milliseconds: -20]
      moved = Sally.device_move_aliases(move_opts)

      assert {:ok, %Sally.Device{ident: moved_ident} = moved_device} = moved

      # verify the two devices were indeed different
      assert src_ident != moved_ident

      all_equal =
        for %Sally.DevAlias{name: name} <- ctx.dev_alias,
            %Sally.DevAlias{name: moved_name} when moved_name == name <- moved_device.aliases do
          true
        end

      assert Enum.all?(all_equal, fn x -> x end)
    end
  end

  describe "Sally.Device.latest/1" do
    @tag host_add: [], device_add: [auto: :pwm]
    test "finds a recently created device", ctx do
      assert %{device: %{id: device_id}} = ctx

      latest = Sally.Device.latest(milliseconds: -20, schema: true)

      assert %{id: ^device_id} = latest
    end

    test "returns nil when no latest device" do
      latest = Sally.Device.latest(milliseconds: -5)

      refute latest
    end
  end
end
