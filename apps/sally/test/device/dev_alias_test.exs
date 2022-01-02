defmodule SallyDevAliasTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_dev_alias: true

  setup_all do
    # always create and setup a host
    {:ok, %{host_add: [], host_setup: []}}
  end

  setup [:host_add, :host_setup, :device_add, :devalias_add, :devalias_just_saw]
  setup [:command_add, :datapoint_add, :dispatch_add]

  describe "Sally.device_add_alias/1" do
    @tag device_add: [auto: :mcp23008]
    test "detects missing options", %{device: device} do
      assert {:error, text} = Sally.device_add_alias(name: Sally.DevAliasAid.unique(:devalias))
      assert text =~ ~r/:device missing/

      assert {:error, text} = Sally.device_add_alias(device: device.ident)
      assert text =~ ~r/name/

      assert {:error, text} =
               Sally.device_add_alias(device: device.ident, name: Sally.DevAliasAid.unique(:devalias))

      assert text =~ ~r/pio/
    end

    test "detects missing device" do
      assert {:not_found, text} =
               Sally.device_add_alias(device: "ds.missing", name: Sally.DevAliasAid.unique(:devalias))

      assert text =~ ~r/ds.missing/
    end

    @tag device_add: [auto: :mcp23008]
    test "handles changeset errors", %{device: device} do
      opts = [device: device.ident, name: Sally.DevAliasAid.unique(:dev_alias), pio: -1]
      assert {:error, [{:pio, _}]} = Sally.device_add_alias(opts)
    end

    @tag device_add: [auto: :mcp23008], devalias_add: [], just_saw: []
    test "detects duplicate name", %{device: device, dev_alias: dev_alias} do
      taken_name = dev_alias.name

      opts = [device: device.ident, name: dev_alias.name]
      assert {:name_taken, ^taken_name} = Sally.device_add_alias(opts)
    end
  end

  describe "Sally.devalias_delete/1" do
    @tag device_add: [auto: :mcp23008], devalias_add: [], just_saw: []
    @tag command_add: [count: 250, shift_unit: :days, shift_increment: -1]
    test "deletes a mutable DevAlias name", ctx do
      assert %Sally.DevAlias{name: to_delete_name} = ctx.dev_alias

      assert {:ok, [{:name, ^to_delete_name}, {:commands, _}, {:datapoints, _}, {:alfred, _}]} =
               Sally.devalias_delete(to_delete_name)
    end

    @tag device_add: [auto: :ds], devalias_add: [], just_saw: []
    @tag datapoint_add: [count: 250, shift_unit: :days, shift_increment: -1]
    test "deletes an immutable DevAlias name", ctx do
      assert %Sally.DevAlias{name: to_delete_name} = ctx.dev_alias

      assert {:ok, [{:name, ^to_delete_name}, {:commands, _}, {:datapoints, _}, {:alfred, _}]} =
               Sally.devalias_delete(to_delete_name)
    end
  end

  @tag device_add: [auto: :ds], devalias_add: [], just_saw: []
  test "Sally.devalias_info/2 returns summarized and raw results", %{device: device, host: host} do
    assert %Sally.Host{
             name: host_name,
             ident: host_ident,
             profile: host_profile,
             last_seen_at: host_last_seen_at
           } = host

    assert %Sally.Device{ident: dev_ident, last_seen_at: dev_last_seen_at} = device

    name = Sally.DevAliasAid.unique(:dev_alias)

    assert %Sally.DevAlias{name: ^name, pio: dev_alias_pio, ttl_ms: dev_alias_ttl_ms} =
             Sally.device_add_alias(device: device.ident, name: name)

    assert %{
             cmd: %{},
             description: "<none>",
             name: ^name,
             pio: ^dev_alias_pio,
             ttl_ms: ^dev_alias_ttl_ms,
             host: %{
               name: ^host_name,
               ident: ^host_ident,
               profile: ^host_profile,
               last_seen_at: ^host_last_seen_at
             },
             device: %{ident: ^dev_ident, last_seen_at: ^dev_last_seen_at}
           } = Sally.devalias_info(name)
  end

  describe "Sally.devalias_rename/1 handles" do
    @tag device_add: [auto: :mcp23008], devalias_add: [count: 2], just_saw: []
    test "when the to name is taken", %{dev_alias: dev_aliases} do
      assert [%Sally.DevAlias{name: from}, %Sally.DevAlias{name: to}] = dev_aliases

      assert {:name_taken, ^to} = Sally.devalias_rename(from: from, to: to)
    end

    @tag device_add: [auto: :ds], devalias_add: [], just_saw: []
    test "when the new name is available", %{dev_alias: dev_alias} do
      # first, test Host performs the rename
      new_name = Sally.DevAliasAid.unique(:dev_alias)

      assert %Sally.DevAlias{name: ^new_name} = Sally.DevAlias.rename(from: dev_alias.name, to: new_name)

      # second, test Sally.dev_alias_rename recognizes success
      assert :ok = Sally.devalias_rename(from: new_name, to: Sally.DevAliasAid.unique(:dev_alias))
    end

    test "when requested dev_alias name is unavailable" do
      unavailable = Sally.DevAliasAid.unique(:dev_alias)

      assert {:not_found, ^unavailable} =
               Sally.devalias_rename(from: unavailable, to: Sally.DevAliasAid.unique(:dev_alias))
    end

    test "when opts are invalid" do
      assert {:bad_args, _} = Sally.devalias_rename([])
    end
  end

  @tag skip: true
  @tag device_add: [auto: :mcp23008], devalias_add: [count: 5], command_add: [count: 100]
  test "Sally.DevAlias.explain/2", ctx do
    %Sally.DevAlias{name: name} = ctx.dev_alias |> List.first()

    Sally.DevAlias.explain(name)
  end
end
