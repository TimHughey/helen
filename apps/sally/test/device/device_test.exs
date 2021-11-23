defmodule Sally.DeviceTest do
  # can not use async: true due to indirect use of Sally.device_latest/1
  use ExUnit.Case
  use Should

  alias Sally.{Device, DevAlias, Host}
  alias Sally.Test.Support

  @moduletag db_test: true, sally_device: true

  setup [:create_host]

  @tag create_host: true
  test "Sally.device_move_aliases/1 moves aliases from src to dest ident", %{host: host} do
    src_dev = Support.add_device(host, auto: :mcp23008)
    should_be_struct(src_dev, Device)

    dest_dev = Support.add_device(host, auto: :mcp23008)
    should_be_struct(dest_dev, Device)

    dev_aliases =
      for pio <- 0..4 do
        dev_alias_opts = [
          device: src_dev.ident,
          name: Support.unique(:name),
          pio: pio,
          description: "test move dev alias"
        ]

        dev_alias = Sally.device_add_alias(dev_alias_opts)
        should_be_struct(dev_alias, DevAlias)

        dev_alias
      end

    should_be_non_empty_list(dev_aliases)

    res = Sally.device_move_aliases(from: src_dev.ident, to: dest_dev.ident)
    should_be_ok_tuple_with_schema(res, Device)

    {:ok, updated_dev} = res

    refute src_dev.id == updated_dev.id, "updated device id should not be equal to src device id"

    all_equal =
      for %DevAlias{name: name} <- dev_aliases,
          %DevAlias{name: moved_name} when moved_name == name <- updated_dev.aliases do
        true
      end

    assert Enum.all?(all_equal, fn x -> x end)
  end

  @tag create_host: true
  test "Sally.device_move_aliases/1 moves aliases from src to latest device discovered", %{host: host} do
    src_dev = Support.add_device(host, auto: :mcp23008)
    should_be_struct(src_dev, Device)

    dest_dev = Support.add_device(host, auto: :mcp23008)
    should_be_struct(dest_dev, Device)

    dev_aliases =
      for pio <- 0..4 do
        dev_alias_opts = [
          device: src_dev.ident,
          name: Support.unique(:name),
          pio: pio,
          description: "test move dev alias"
        ]

        dev_alias = Sally.device_add_alias(dev_alias_opts)
        should_be_struct(dev_alias, DevAlias)

        dev_alias
      end

    should_be_non_empty_list(dev_aliases)

    res = Sally.device_move_aliases(from: src_dev.ident, to: :latest)
    should_be_ok_tuple_with_schema(res, Device)

    {:ok, updated_dev} = res

    refute src_dev.id == updated_dev.id, "updated device id should not be equal to src device id"
    should_be_equal(dest_dev.ident, updated_dev.ident)

    all_equal =
      for %DevAlias{name: name} <- dev_aliases,
          %DevAlias{name: moved_name} when moved_name == name <- updated_dev.aliases do
        true
      end

    assert Enum.all?(all_equal, fn x -> x end)
  end

  defp create_host(%{create_host: true} = ctx) do
    host = Support.add_host([])
    should_be_schema(host, Host)

    Map.merge(%{host: host}, ctx)
  end

  defp create_host(ctx), do: ctx
end
