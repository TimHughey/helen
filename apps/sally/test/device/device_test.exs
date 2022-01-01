defmodule Sally.DeviceTest do
  # can not use async: true due to indirect use of Sally.device_latest/1
  use ExUnit.Case
  use Sally.TestAid

  @moduletag sally: true, sally_device: true

  setup_all do
    # always create and setup a host
    {:ok, %{host_add: [], host_setup: []}}
  end

  setup [:host_add, :host_setup, :device_add, :devalias_add, :devalias_just_saw]

  describe "Sally.device_move_aliases/1" do
    @tag device_add: [auto: :mcp23008], devalias_add: [count: 8]
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

    @tag device_add: [auto: :mcp23008], devalias_add: [count: 8]
    test "moves aliases to the latest device created", ctx do
      %{host: host, device: %Sally.Device{ident: src_ident}} = ctx

      # create a second device to serve as the destination
      add_ctx = %{host: host, device_add: [auto: :mcp23008]}
      assert %{device: %Sally.Device{}} = Sally.DeviceAid.add(add_ctx)

      move_opts = [from: src_ident, to: :latest]

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
  end
end
