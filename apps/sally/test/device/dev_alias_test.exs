defmodule SallyDevAliasTest do
  # can not use async: true due to indirect use of Sally.device_latest/1
  use ExUnit.Case
  use Should
  use Sally.TestAids

  @moduletag sally: true, sally_dev_alias: true

  alias Sally.DevAlias

  setup_all do
    # always create and setup a host
    {:ok, %{host_add: [], host_setup: []}}
  end

  setup [:host_add, :host_setup, :device_add, :devalias_add, :devalias_just_saw]
  setup [:command_add, :datapoint_add, :dispatch_add]

  describe "Sally.device_add_alias/1" do
    @tag device_add: [auto: :mcp23008]
    test "detects missing options", %{device: device} do
      opts = [name: DevAliasAid.unique(:devalias)]
      Sally.device_add_alias(opts) |> Should.Be.Tuple.with_rc_and_binaries(:error, "device")

      opts = [device: device.ident]
      Sally.device_add_alias(opts) |> Should.Be.Tuple.with_rc_and_binaries(:error, "name")

      opts = [device: device.ident, name: DevAliasAid.unique(:devalias)]
      Sally.device_add_alias(opts) |> Should.Be.Tuple.with_rc_and_binaries(:error, "pio")
    end

    test "detects missing device" do
      opts = [device: "ds.missing", name: DevAliasAid.unique(:devalias)]
      Sally.device_add_alias(opts) |> Should.Be.Tuple.with_rc_and_binaries(:not_found, "missing")
    end

    @tag device_add: [auto: :mcp23008]
    test "handles changeset errors", %{device: device} do
      opts = [device: device.ident, name: DevAliasAid.unique(:dev_alias), pio: -1]
      Sally.device_add_alias(opts) |> Should.Be.Tuple.with_rc(:error) |> Should.Be.NonEmpty.list()
    end

    @tag device_add: [auto: :mcp23008], devalias_add: [], just_saw: []
    test "detects duplicate name", %{device: device, dev_alias: dev_alias} do
      opts = [device: device.ident, name: dev_alias.name]
      Sally.device_add_alias(opts) |> Should.Be.Tuple.with_rc_and_binaries(:name_taken, dev_alias.name)
    end

    @tag device_add: [auto: :ds]
    test "creates alias to latest device discovered", %{device: device} do
      opts = [device: :latest, name: DevAliasAid.unique(:dev_alias)]
      dev_alias = Sally.device_add_alias(opts) |> Should.Be.schema(DevAlias)

      dev_alias = DevAlias.load_device(dev_alias) |> Should.Be.schema(DevAlias)
      Should.Be.asserted(fn -> dev_alias.device.ident == device.ident end)
    end
  end

  describe "Sally.devalias_delete/1" do
    @tag device_add: [auto: :mcp23008], devalias_add: [], just_saw: []
    @tag command_add: [count: 1000, shift_unit: :days, shift_increment: -1]
    test "deletes a mutable DevAlias name", ctx do
      ctx.dev_alias.name
      |> Sally.devalias_delete()
      |> Should.Be.Tuple.with_rc_and_list(:ok)
      |> Should.Be.NonEmpty.list()
    end

    @tag device_add: [auto: :ds], devalias_add: [], just_saw: []
    @tag datapoint_add: [count: 1000, shift_unit: :days, shift_increment: -1]
    test "deletes an immutable DevAlias name", ctx do
      ctx.dev_alias.name
      |> Sally.devalias_delete()
      |> Should.Be.Tuple.with_rc_and_list(:ok)
      |> Should.Be.NonEmpty.list()
    end
  end

  @tag device_add: [auto: :ds], devalias_add: [], just_saw: []
  test "Sally.devalias_info/2 returns summarized and raw results", %{device: device, host: host} do
    opts = [device: device.ident, name: DevAliasAid.unique(:dev_alias)]
    dev_alias = Sally.device_add_alias(opts) |> Should.Be.schema(DevAlias)

    to_match = %{
      cmd: %{},
      description: "<none>",
      name: dev_alias.name,
      pio: dev_alias.pio,
      ttl_ms: dev_alias.ttl_ms,
      host: %{name: host.name, ident: host.ident, profile: host.profile, last_seen_at: host.last_seen_at},
      device: %{ident: device.ident, last_seen_at: device.last_seen_at}
    }

    Sally.devalias_info(dev_alias.name) |> Should.Be.match(to_match)
  end

  describe "Sally.devalias_rename/1 handles" do
    @tag device_add: [auto: :mcp23008], devalias_add: [count: 2], just_saw: []
    test "when the to name is taken", %{dev_alias: dev_aliases} do
      [%DevAlias{name: from}, %DevAlias{name: to}] = dev_aliases

      opts = [from: from, to: to]
      Sally.devalias_rename(opts) |> Should.Be.Tuple.with_rc_and_binaries(:name_taken, to)
    end

    @tag device_add: [auto: :ds], devalias_add: [], just_saw: []
    test "when the new name is available", %{dev_alias: dev_alias} do
      # first, test Host performs the rename
      opts = [from: dev_alias.name, to: DevAliasAid.unique(:dev_alias)]
      DevAlias.rename(opts) |> Should.Be.Schema.with_all_key_value(DevAlias, name: opts[:to])

      # second, test Sally.dev_alias_rename recognizes success
      opts = [from: opts[:to], to: DevAliasAid.unique(:dev_alias)]
      Sally.devalias_rename(opts) |> Should.Be.match(:ok)
    end

    test "when requested dev_alias name is unavailable" do
      # first, test Host performs the rename
      opts = [from: DevAliasAid.unique(:dev_alias), to: DevAliasAid.unique(:dev_alias)]
      Sally.devalias_rename(opts) |> Should.Be.Tuple.with_rc_and_binaries(:not_found, opts[:from])
    end

    test "when opts are invalid" do
      Sally.devalias_rename([]) |> Should.Be.Tuple.with_rc(:bad_args)
    end
  end
end
