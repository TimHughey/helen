defmodule SallyDevAliasTest do
  # can not use async: true due to indirect use of Sally.device_latest/1
  use ExUnit.Case
  use Should

  @moduletag db_test: true, sally_dev_alias: true

  alias Sally.{DevAlias, Device, Host}
  alias Sally.Test.Support

  setup_all ctx do
    ctx
  end

  setup [:create_device]

  @tag create_device: true
  @tag family: :ds
  test "Sally.device_add_alias/1 creates an alias to a mutable device", %{device: device} do
    opts = [device: device.ident, name: Support.unique(:dev_alias)]
    dev_alias = Sally.device_add_alias(opts)

    should_be_schema(dev_alias, DevAlias)
    should_be_equal(dev_alias.name, opts[:name])
    should_be_equal(dev_alias.pio, 0)
  end

  @tag create_device: true
  @tag family: :mcp23008
  test "Sally.device_add_alias/1 detects missing options", %{device: device} do
    opts = [name: Support.unique(:dev_alias)]
    res = Sally.device_add_alias(opts)
    should_be_error_tuple_with_binary(res, "device")

    opts = [device: device.ident]
    res = Sally.device_add_alias(opts)
    should_be_error_tuple_with_binary(res, "name")

    opts = [device: device.ident, name: Support.unique(:dev_alias)]
    res = Sally.device_add_alias(opts)
    should_be_error_tuple_with_binary(res, "pio")
  end

  test "Sally.device_add_alias/1 detects missing device" do
    opts = [device: Support.unique(:ds), name: Support.unique(:dev_alias)]
    res = Sally.device_add_alias(opts)
    should_be_not_found_tuple_with_binary(res, opts[:device])
  end

  @tag create_device: true
  @tag family: :mcp23008
  test "Sally.device_add_alias/1 handles changeset errors", %{device: device} do
    opts = [device: device.ident, name: Support.unique(:dev_alias), pio: -1]
    res = Sally.device_add_alias(opts)
    should_be_error_tuple(res)

    {:error, errors} = res
    should_be_non_empty_list(errors)
  end

  @tag create_device: true
  @tag family: :ds
  test "Sally.device_add_alias/1 detects duplicate name", %{device: device} do
    dev_alias = Support.unique(:dev_alias)

    %Alfred.JustSaw{seen_list: [%Alfred.JustSaw.Alias{name: dev_alias, ttl_ms: 15_000}]}
    |> Alfred.just_saw()

    opts = [device: device.ident, name: dev_alias]
    res = Sally.device_add_alias(opts)
    should_be_tuple_with_size(res, 2)
    should_be_tuple_with_rc(res, :name_taken)
    {:name_taken, msg} = res

    assert String.contains?(msg, dev_alias), "#{msg} should contain #{dev_alias}"
  end

  @tag create_device: true
  @tag family: :ds
  test "Sally.device_add_alias/1 can create alias to latest device discovered", %{device: device} do
    opts = [device: :latest, name: Support.unique(:dev_alias)]
    res = Sally.device_add_alias(opts)
    should_be_schema(res, DevAlias)

    dev_alias = DevAlias.load_device(res)
    should_be_schema(dev_alias, DevAlias)
    should_be_equal(dev_alias.device.ident, device.ident)
  end

  defp create_device(%{create_device: true, family: family} = ctx) do
    host = Support.add_host([])
    should_be_schema(host, Host)

    device = Support.add_device(host, auto: family)
    should_be_schema(device, Device)

    Map.merge(%{host: host, device: device}, ctx)
  end

  defp create_device(ctx), do: ctx
end
