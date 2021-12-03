defmodule Sally.DeviceTest do
  # can not use async: true due to indirect use of Sally.device_latest/1
  use ExUnit.Case
  use Should
  use Sally.TestAid

  @moduletag sally: true, sally_device: true

  alias Sally.{DevAlias, Device}

  setup_all do
    # always create and setup a host
    {:ok, %{host_add: [], host_setup: []}}
  end

  setup [:host_add, :host_setup, :device_add, :devalias_add, :devalias_just_saw]

  describe "Sally.device_move_aliases/1" do
    @tag device_add: [auto: :mcp23008], devalias_add: [count: 8]
    test "moves aliases from src to dest ident", ctx do
      %{host: host, device: src_device} = ctx

      # create a second device to serve as the destination
      add_ctx = %{host: host, device_add: [auto: :mcp23008]}
      %{device: dest_device} = DeviceAid.add(add_ctx)
      Should.Be.schema(dest_device, Device)

      move_opts = [from: src_device.ident, to: dest_device.ident]

      moved_device =
        Sally.device_move_aliases(move_opts)
        |> Should.Be.Tuple.with_rc_and_schema(:ok, Device)

      # verify the two devices were indeed different
      Should.Be.asserted(fn -> src_device.ident != moved_device.ident end)

      all_equal =
        for %DevAlias{name: name} <- ctx.dev_alias,
            %DevAlias{name: moved_name} when moved_name == name <- moved_device.aliases do
          true
        end

      assert Enum.all?(all_equal, fn x -> x end)
    end

    @tag device_add: [auto: :mcp23008], devalias_add: [count: 8]
    test "moves aliases to the latest device created", ctx do
      %{host: host, device: src_device} = ctx

      # create a second device to serve as the destination
      add_ctx = %{host: host, device_add: [auto: :mcp23008]}
      %{device: dest_device} = DeviceAid.add(add_ctx)
      Should.Be.schema(dest_device, Device)

      move_opts = [from: src_device.ident, to: :latest]

      moved_device =
        Sally.device_move_aliases(move_opts)
        |> Should.Be.Tuple.with_rc_and_schema(:ok, Device)

      # verify the two devices were indeed different
      Should.Be.asserted(fn -> src_device.ident != moved_device.ident end)

      all_equal =
        for %DevAlias{name: name} <- ctx.dev_alias,
            %DevAlias{name: moved_name} when moved_name == name <- moved_device.aliases do
          true
        end

      assert Enum.all?(all_equal, fn x -> x end)
    end
  end
end
