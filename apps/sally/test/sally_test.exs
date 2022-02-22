defmodule SallyTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduledoc sally: true, sally_api: true

  setup [:host_add, :device_add, :dev_alias_add]

  ##
  ## DevAlias
  ##

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

  describe "Sally.devalias_names/1" do
    @tag dev_alias_add: [auto: :ds]
    test "returns list of immutable names", ctx do
      assert %{dev_alias: %{name: name}} = ctx

      names = Sally.devalias_names(:imm)

      assert Enum.any?(names, &match?(^name, &1))
      assert Enum.count(names) > 0
    end

    @tag dev_alias_add: [auto: :pwm]
    test "returns list of mutable names", ctx do
      assert %{dev_alias: %{name: name}} = ctx

      names = Sally.devalias_names(:mut)

      assert Enum.any?(names, &match?(^name, &1))
      assert Enum.count(names) >= 1
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

  describe "Sally.ttl_adjust/2" do
    @tag dev_alias_add: [auto: :ds]
    test "changes ttl for a list of immutables", ctx do
      assert %{device: %{ident: ident}} = ctx
      %{aliases: [_] = dev_aliases} = Sally.Device.find(ident) |> Sally.Device.preload()

      names = Enum.map(dev_aliases, &Map.get(&1, :name))

      adjusted = Sally.ttl_adjust(names, 9997)

      assert Enum.count(names) == Enum.count(adjusted)
    end

    @tag dev_alias_add: [auto: :pwm, count: 4]
    test "changes ttl for a list of mutables", ctx do
      assert %{device: %{ident: ident}} = ctx
      %{aliases: [_ | _] = dev_aliases} = Sally.Device.find(ident) |> Sally.Device.preload()

      names = Enum.map(dev_aliases, &Map.get(&1, :name))

      adjusted = Sally.ttl_adjust(names, 9998)

      assert Enum.count(names) == Enum.count(adjusted)
    end
  end

  ##
  ## Device
  ##

  describe "Sally.device_add_alias/1" do
    @tag host_add: [], device_add: [auto: :mcp23008], dev_alias_add: false
    test "detects missing options", ctx do
      assert %{device: %{ident: ident}} = ctx

      opts_no_name = []
      assert_raise(RuntimeError, ~r/:name/, fn -> Sally.device_add_alias(ident, opts_no_name) end)

      opts_no_pio = [name: Sally.DevAliasAid.unique(:devalias)]
      assert_raise(RuntimeError, ~r/:pio/, fn -> Sally.device_add_alias(ident, opts_no_pio) end)
    end

    test "detects missing device" do
      ident = "ds.missing"
      opts = [name: Sally.DevAliasAid.unique(:devalias)]

      assert_raise(RuntimeError, ~r/ds.missing/, fn -> Sally.device_add_alias(ident, opts) end)
    end

    @tag host_add: [], device_add: [auto: :mcp23008], dev_alias_add: false
    test "handles changeset errors", ctx do
      assert %{device: %{ident: ident}} = ctx
      opts = [name: Sally.DevAliasAid.unique(:dev_alias), pio: -1]

      assert_raise(Ecto.InvalidChangesetError, fn -> Sally.device_add_alias(ident, opts) end)
    end

    @tag dev_alias_add: [auto: :pwm]
    test "detects duplicate name", ctx do
      %{device: %{ident: ident}, dev_alias: %{name: taken_name}} = ctx

      opts = [name: taken_name]
      assert_raise(RuntimeError, ~r/taken/, fn -> Sally.device_add_alias(ident, opts) end)
    end
  end

  ##
  ## Host
  ##

  describe "Sally.host_ota/2" do
    @tag host_add: []
    test "invokes an OTA for a known host name (default opts)", ctx do
      %{host: %{name: name}} = ctx

      assert <<_::binary>> = Sally.host_ota(name)
    end
  end

  describe "Sally.host_ota_live/1" do
    @tag host_add: []
    test "invokes an OTA for live hosts with default opts", ctx do
      %{host: %{name: name}} = ctx

      names = Sally.host_ota_live(echo: :instruct)
      assert [<<_::binary>> | _] = names
      assert Enum.any?(names, &match?(^name, &1))

      assert_receive(%{data: data, subsystem: "host"} = instruct, 1)

      assert %{filters: ["ota"]} = instruct
      assert %{ident: <<"host."::binary, _::binary>>} = instruct
      assert %{packed_length: packed_length} = instruct
      assert packed_length < 100

      assert %{file: <<"00"::binary, _::binary>>, valid_ms: 60_000} = data
    end
  end

  describe "Sally.host_rename/2" do
    test "handles from host not found" do
      from = Sally.HostAid.unique(:name)
      to = Sally.HostAid.unique(:name)

      assert {:not_found, ^from} = Sally.host_rename(from, to)
    end

    @tag host_add: []
    test "handles success", ctx do
      %{host: %Sally.Host{name: from}} = ctx
      # create unique new name
      to = Sally.HostAid.unique(:name)
      assert %{name: ^to} = Sally.host_rename(from, to)
    end
  end

  describe "Sally.host_retire/1" do
    @tag host_add: []
    test "retires a host", ctx do
      assert %{host: host} = ctx
      assert %Sally.Host{name: retire_name, ident: retire_ident} = host

      assert {:ok, %Sally.Host{} = host} = Sally.host_retire(retire_name)

      assert %{authorized: false, ident: ^retire_ident, reset_reason: "retired"} = host
    end
  end

  describe "Sally.host_restart/2" do
    @tag host_add: []
    test "invokes a restart for a known host name (default opts)", ctx do
      %{host: %{name: name}} = ctx

      assert <<_::binary>> = Sally.host_restart(name)
    end
  end

  describe "Sally.host_restart_live/1" do
    @tag host_add: []
    test "invokes a restart for live hosts (default opts)", ctx do
      %{host: %{name: name}} = ctx

      names = Sally.host_restart_live(echo: :instruct)
      assert [<<_::binary>> | _] = names
      assert Enum.any?(names, &match?(^name, &1))

      assert_receive(%{data: %{}, subsystem: "host"} = instruct, 1)

      assert %{filters: ["restart"]} = instruct
      assert %{ident: <<"host."::binary, _::binary>>} = instruct
      assert %{packed_length: packed_length} = instruct
      assert packed_length < 100
    end
  end
end
