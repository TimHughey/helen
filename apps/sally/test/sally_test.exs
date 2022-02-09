defmodule SallyTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduledoc sally: true, sally_api: true

  setup [:host_add, :device_add, :dev_alias_add]

  describe "Sally.devalias_delete/1" do
    @tag skip: false
    @tag dev_alias_add: [auto: :mcp23008, cmds: [history: 50, minutes: -11]]
    test "deletes a mutable DevAlias name", ctx do
      assert %{dev_alias: %{name: name}} = ctx

      assert {:ok, info} = Sally.devalias_delete(name)
      assert %{name: ^name, cmds: purged, unregister: :ok} = info
      assert purged == 50
    end

    @tag skip: false
    @tag dev_alias_add: [auto: :ds, daps: [history: 50, minutes: -11]]
    test "deletes an immutable DevAlias name", ctx do
      assert %{dev_alias: %{name: name}} = ctx

      assert {:ok, info} = Sally.devalias_delete(name)
      assert %{name: ^name, datapoints: purged, unregister: :ok} = info
      assert purged == 50
    end
  end

  describe "Sally.devalias_info/2" do
    @tag dev_alias_add: [auto: :pwm, cmds: [history: 2]]
    test "Sally.devalias_info/2 returns summarized and raw results", ctx do
      assert %{dev_alias: %{name: <<_::binary>> = name}} = ctx

      info = Sally.devalias_info(name)

      assert %{cmd: _, device: _, host: _, name: ^name} = info
    end
  end

  describe "Sally.devalias_rename/1 handles" do
    @tag dev_alias_add: [auto: :mcp23008, count: 2]
    test "when the to name is taken", %{dev_alias: dev_aliases} do
      assert [%Sally.DevAlias{name: from}, %Sally.DevAlias{name: to}] = dev_aliases

      assert {:name_taken, ^to} = Sally.devalias_rename(from: from, to: to)
    end

    @tag device_add: [auto: :ds], devalias_add: []
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

  describe "Sally.device_add_alias/1" do
    @tag host_add: [], device_add: [auto: :mcp23008], dev_alias_add: false
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

    @tag host_add: [], device_add: [auto: :mcp23008], dev_alias_add: false
    test "handles changeset errors", %{device: device} do
      opts = [device: device.ident, name: Sally.DevAliasAid.unique(:dev_alias), pio: -1]

      assert_raise(Ecto.InvalidChangesetError, fn ->
        Sally.device_add_alias(opts)
      end)
    end

    @tag dev_alias_add: [auto: :pwm]
    test "detects duplicate name", %{device: device, dev_alias: dev_alias} do
      taken_name = dev_alias.name

      opts = [device: device.ident, name: dev_alias.name]
      assert {:name_taken, ^taken_name} = Sally.device_add_alias(opts)
    end
  end
end
