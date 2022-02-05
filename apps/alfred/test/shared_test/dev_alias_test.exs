defmodule Alfred.DevAliasAid.Test do
  use ExUnit.Case, async: true
  use Alfred.TestAid

  @moduletag alfred: true, alfred_dev_alias: true

  setup [:equipment_add, :sensor_add, :sensors_add]

  describe "Alfred.DevAlias.new/1" do
    @tag sensor_add: []
    test "creates a new registered immutable", ctx do
      assert %{dev_alias: dev_alias} = ctx
      assert %Alfred.DevAlias{name: name, nature: :datapoints, register: pid} = dev_alias
      assert %Alfred.DevAlias{datapoints: [%Alfred.Datapoint{}]} = dev_alias
      assert is_pid(pid) and Process.alive?(pid)

      assert %{name: ^name} = Alfred.name_info(name)
    end

    @tag sensor_add: [register: false]
    test "creates a new unregistered immutable", ctx do
      assert %{dev_alias: dev_alias} = ctx
      assert %Alfred.DevAlias{name: name, nature: :datapoints} = dev_alias
      assert %Alfred.DevAlias{register: :skipped} = dev_alias
      assert %Alfred.DevAlias{datapoints: [%Alfred.Datapoint{}]} = dev_alias

      refute Alfred.name_registered?(name)
    end

    @tag sensors_add: []
    test "creates many new registered immutables", ctx do
      assert %{dev_alias: dev_aliases} = ctx
      assert [%Alfred.DevAlias{} | _] = dev_aliases

      Enum.each(dev_aliases, fn dev_alias ->
        assert %Alfred.DevAlias{name: name, nature: :datapoints, register: pid} = dev_alias
        assert is_pid(pid) and Process.alive?(pid)

        assert %Alfred.DevAlias{datapoints: [%Alfred.Datapoint{}]} = dev_alias
        assert Alfred.name_registered?(name)
      end)
    end

    @tag equipment_add: []
    test "creates a new registered mutable", ctx do
      assert %{dev_alias: dev_alias} = ctx
      assert %Alfred.DevAlias{name: name, nature: :cmds, register: pid} = dev_alias
      assert is_pid(pid) and Process.alive?(pid)
      assert %Alfred.DevAlias{cmds: [%Alfred.Command{}]} = dev_alias

      assert %{name: ^name} = Alfred.name_info(name)
    end

    @tag equipment_add: [register: false]
    test "creates a new unregistered mutable", ctx do
      assert %{dev_alias: dev_alias} = ctx
      assert %Alfred.DevAlias{name: name, nature: :cmds} = dev_alias
      assert %Alfred.DevAlias{register: :skipped} = dev_alias
      assert %Alfred.DevAlias{cmds: [%Alfred.Command{}]} = dev_alias

      refute Alfred.name_registered?(name)
    end

    @tag equipment_add: [rc: :expired]
    test "honors rc: :expired", ctx do
      assert %{dev_alias: dev_alias} = ctx
      assert %Alfred.DevAlias{name: name, nature: :cmds} = dev_alias
      assert %Alfred.DevAlias{ttl_ms: 10} = dev_alias
      assert %Alfred.DevAlias{cmds: [%Alfred.Command{}]} = dev_alias

      assert Alfred.name_registered?(name)
    end

    @tag sensor_add: [rc: :error]
    test "honors rc: :error", ctx do
      assert %{dev_alias: dev_alias} = ctx
      assert %Alfred.DevAlias{name: name, nature: :datapoints} = dev_alias
      assert %Alfred.DevAlias{ttl_ms: 13} = dev_alias

      assert Alfred.name_registered?(name)
    end

    @tag equipment_add: [rc: :timeout]
    test "honors rc: :timeout", ctx do
      assert %{dev_alias: dev_alias} = ctx
      assert %Alfred.DevAlias{name: name, nature: :cmds} = dev_alias
      assert %Alfred.DevAlias{ttl_ms: 5001} = dev_alias

      assert Alfred.name_registered?(name)
    end
  end
end
