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

  setup [:create_device, :create_dev_alias]

  describe "Sally.device_add_alias/1" do
    @tag create_device: true
    @tag family: :ds
    test "creates an alias to a mutable device", %{device: device} do
      opts = [device: device.ident, name: Support.unique(:dev_alias)]
      dev_alias = Sally.device_add_alias(opts)

      should_be_schema(dev_alias, DevAlias)
      should_be_equal(dev_alias.name, opts[:name])
      should_be_equal(dev_alias.pio, 0)
    end

    @tag create_device: true
    @tag family: :mcp23008
    test "detects missing options", %{device: device} do
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

    test "detects missing device" do
      opts = [device: Support.unique(:ds), name: Support.unique(:dev_alias)]
      res = Sally.device_add_alias(opts)
      should_be_not_found_tuple_with_binary(res, opts[:device])
    end

    @tag create_device: true
    @tag family: :mcp23008
    test "handles changeset errors", %{device: device} do
      opts = [device: device.ident, name: Support.unique(:dev_alias), pio: -1]
      res = Sally.device_add_alias(opts)
      should_be_error_tuple(res)

      {:error, errors} = res
      should_be_non_empty_list(errors)
    end

    @tag create_device: true
    @tag family: :ds
    test "detects duplicate name", %{device: device} do
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
    test "creates alias to latest device discovered", %{device: device} do
      opts = [device: :latest, name: Support.unique(:dev_alias)]
      res = Sally.device_add_alias(opts)
      should_be_schema(res, DevAlias)

      dev_alias = DevAlias.load_device(res)
      should_be_schema(dev_alias, DevAlias)

      should_be_equal(dev_alias.device.ident, device.ident)
    end
  end

  @tag create_device: true
  @tag family: :ds
  test "Sally.devalias_info/2 returns summarized and raw results", %{device: device} do
    device = Device.load_host(device)

    opts = [device: device.ident, name: Support.unique(:dev_alias)]
    res = Sally.device_add_alias(opts)
    should_be_schema(res, DevAlias)

    summary = Sally.devalias_info(res.name)
    should_be_non_empty_map(summary)

    should_be_equal(summary.name, res.name)
    should_be_equal(summary.pio, res.pio)
    should_be_equal(summary.host.name, device.host.name)
    should_be_equal(summary.host.ident, device.host.ident)
    should_be_equal(summary.host.profile, device.host.profile)
    should_be_equal(summary.device.ident, device.ident)
    should_be_equal(summary.device.last_seen_at, device.last_seen_at)
  end

  describe "Sally.devalias_rename/1 handles" do
    @tag create_device: true
    @tag family: :ds
    @tag create_dev_alias: []
    test "when the to name is taken", %{dev_alias: dev_alias1} do
      # create a second devalias for name taken test
      %{device: second_device} = %{create_device: true, family: :ds} |> create_device()
      %{dev_alias: dev_alias2} = %{create_dev_alias: [], device: second_device} |> create_dev_alias()

      opts = [from: dev_alias1.name, to: dev_alias2.name]
      res = Sally.devalias_rename(opts)

      should_be_tuple_with_rc_and_val(res, :name_taken, dev_alias2.name)
    end

    @tag create_device: true
    @tag family: :ds
    @tag create_dev_alias: []
    test "when the new name is available", %{dev_alias: dev_alias1} do
      # first, test Host performs the rename
      opts = [from: dev_alias1.name, to: Support.unique(:dev_alias)]
      res = DevAlias.rename(opts)

      should_be_schema(res, DevAlias)

      # second, test Sally.dev_alias_rename recognizes success
      opts = [from: opts[:to], to: Support.unique(:name)]
      res = Sally.devalias_rename(opts)

      should_be_simple_ok(res)
    end

    test "when requested dev_alias name is unavailable" do
      # first, test Host performs the rename
      opts = [from: Support.unique(:dev_alias), to: Support.unique(:dev_alias)]
      res = Sally.devalias_rename(opts)

      should_be_not_found_tuple_with_binary(res, opts[:from])
    end

    test "when opts are invalid" do
      res = Sally.devalias_rename([])

      should_be_tuple_with_rc_and_val(res, :bad_args, [])
    end
  end

  defp create_dev_alias(%{create_dev_alias: opts, device: device} = ctx) when is_list(opts) do
    name = opts[:name] || Support.unique(:dev_alias)

    dev_alias = Sally.device_add_alias(device: device.ident, name: name)

    should_be_schema(dev_alias, DevAlias)

    Map.put(ctx, :dev_alias, dev_alias)
  end

  defp create_dev_alias(ctx), do: ctx

  defp create_device(%{create_device: true, family: family} = ctx) do
    host = Support.add_host([])
    should_be_schema(host, Host)

    device = Support.add_device(host, auto: family)
    should_be_schema(device, Device)

    Map.merge(%{host: host, device: device}, ctx)
  end

  defp create_device(ctx), do: ctx
end
