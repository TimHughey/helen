defmodule SallyDevAliasTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_dev_alias: true

  setup [:host_add, :device_add, :dev_alias_add]

  describe "Sally.DevAlias" do
    # NOTE: ensure at least one name exists
    @tag dev_alias_add: [auto: :ds]
    test "names/0 retrurns list of names", ctx do
      %{dev_alias: %{name: name}} = ctx

      names = Sally.DevAlias.names()

      assert Enum.any?(names, &match?(^name, &1))
    end

    # NOTE: ensure at least one name exists
    @tag dev_alias_add: [auto: :ds]
    test "names_begin_with/1", ctx do
      %{dev_alias: %{name: name}} = ctx

      assert <<prefix::binary-size(2), _rest::binary>> = name

      names = Sally.DevAlias.names_begin_with(prefix)

      assert Enum.any?(names, &match?(^name, &1))
      assert Enum.count(names) > 1
    end
  end

  describe "Sally.DevAlias.delete/2" do
    @tag dev_alias_add: [auto: :ds, daps: [history: 30]]
    test "deletes an immutable by name (including datapoints)", ctx do
      assert %{dev_alias: %{name: name}} = ctx

      delete = Sally.DevAlias.delete(name)

      assert {:ok, %{name: ^name, datapoints: count}} = delete

      assert count == 30
    end

    @tag dev_alias_add: [auto: :pwm, cmds: [history: 30]]
    test "deletes a mutable by name (including cmds)", ctx do
      assert %{dev_alias: %{name: name}} = ctx

      delete = Sally.DevAlias.delete(name)

      assert {:ok, %{name: ^name, cmds: count}} = delete

      assert count == 30
    end
  end

  describe "Sally.DevAlias.execute_cmd/2" do
    @tag dev_alias_add: [auto: :mcp23008, count: 8, cmds: [history: 3]]
    test "creates new busy command from Sally.DevAlias", ctx do
      assert %{device: %Sally.Device{ident: device_ident}} = ctx
      assert %{dev_alias: [%{nature: :cmds} | _] = dev_aliases} = ctx

      dev_alias = random_pick(dev_aliases)

      # NOTE: include the echo: true option to receive the final Sally.Host.Instruct
      # for validation
      cmd = random_cmd()
      opts = [cmd: cmd, cmd_opts: [echo: :instruct]]
      execute = Sally.DevAlias.execute_cmd(dev_alias, opts)

      assert {:busy, %{cmd: ^cmd, refid: refid}} = execute

      assert %{pio: pio} = dev_alias

      # NOTE: confirm the Instruct sent
      assert_receive(instruct, 100)

      assert %{client_id: "sally_test"} = instruct
      assert %{data: %{ack: true, cmd: ^cmd, pio: ^pio}} = instruct
      assert %{filters: [^device_ident, ^refid]} = instruct
      assert %{ident: <<"host"::binary, _::binary>>} = instruct
      assert %{name: <<"hostname"::binary, _::binary>>} = instruct
      assert %{packed_length: packed_length, subsystem: "i2c"} = instruct
      assert packed_length < 45

      assert Alfred.Track.tracked?(refid)
    end

    @tag dev_alias_add: [auto: :mcp23008, cmds: [history: 3, minutes: -1]]
    test "creates new acked command from Sally.DevAlias", ctx do
      assert %{dev_alias: %Sally.DevAlias{} = dev_alias} = ctx

      cmd = random_cmd()
      opts = [cmd: cmd, cmd_opts: [ack: :immediate]]

      execute_cmd = Sally.DevAlias.execute_cmd(dev_alias, opts)
      assert {:ok, %{cmd: ^cmd}} = execute_cmd
    end
  end

  describe "Sally.DevAlias.load_alias/1" do
    @tag dev_alias_add: [auto: :ds, daps: [history: 3]]
    test "accepts a name", ctx do
      %{dev_alias: %{id: id, name: name, nature: nature}} = ctx

      dev_alias = Sally.DevAlias.load_alias(name)

      assert %{id: ^id, name: ^name, seen_at: %DateTime{}} = dev_alias
      assert %{nature: ^nature} = dev_alias
    end

    @tag dev_alias_add: [auto: :pwm, cmds: [history: 3]]
    test "accepts an id", ctx do
      %{dev_alias: %{id: id, name: name, nature: nature}} = ctx

      dev_alias = Sally.DevAlias.load_alias(name)

      assert %{id: ^id, name: ^name, seen_at: %DateTime{}} = dev_alias
      assert %{nature: ^nature} = dev_alias
    end
  end

  describe "Sally.DevAlias.load_aliases/1" do
    @tag dev_alias_add: [auto: :pwm, count: 4, cmds: [history: 3]]
    test "populates nature virtual field", ctx do
      assert %{device: %Sally.Device{} = device} = ctx

      aliases = Sally.DevAlias.load_aliases(device)

      assert Enum.all?(aliases, &match?(%{nature: :cmds}, &1))
    end
  end

  describe "Sally.DevAlias.nature_ids/2" do
    @tag dev_alias_add: [auto: :ds, daps: [history: 10, seconds: -2]]
    test "returns ids for :nature == :datapoints", ctx do
      %{dev_alias: %{name: name}} = ctx

      query = Sally.DevAlias.nature_ids_query(name, seconds: -1)

      ids = Sally.Repo.all(query)

      assert Enum.count(ids) == 9
      Enum.each(ids, fn id -> assert is_integer(id) end)
    end

    @tag dev_alias_add: [auto: :pwm, cmds: [history: 20]]
    test "returns ids for :nature == :cmds", ctx do
      %{dev_alias: %{name: name}} = ctx

      query = Sally.DevAlias.nature_ids_query(name, milliseconds: -1)

      ids = Sally.Repo.all(query)

      assert Enum.count(ids) > 15
      Enum.each(ids, fn id -> assert is_integer(id) end)
    end
  end

  describe "Sally.DevAlias.status_lookup/3" do
    @tag dev_alias_add: [auto: :mcp23008, cmds: [history: 50, minutes: -1]]
    test "handles a DevAlias with Commands", ctx do
      assert %{dev_alias: %Sally.DevAlias{name: name}} = ctx
      assert %{cmd_latest: %Sally.Command{id: cmd_id, cmd: cmd}} = ctx

      dev_alias = Sally.DevAlias.status_lookup(%{name: name, nature: :cmds}, [])

      assert %Sally.DevAlias{status: status} = dev_alias
      assert %{id: ^cmd_id, cmd: ^cmd} = status
    end

    @tag dev_alias_add: [auto: :ds, daps: [history: 50, seconds: -7]]
    test "handles DevAlias with Datapoints", ctx do
      assert %{dev_alias: %Sally.DevAlias{name: name}} = ctx
      assert %{name_reg: %{name: ^name}} = ctx

      dev_alias = Sally.DevAlias.status_lookup(%{name: name, nature: :datapoints}, [])

      assert %Sally.DevAlias{status: status} = dev_alias
      assert %{relhum: relhum, temp_c: temp_c, temp_f: temp_f} = status
      assert is_float(temp_f)
      assert is_float(temp_c)
      assert is_float(relhum)
    end
  end

  describe "Sally.DevAlias.ttl_adjust/2" do
    @tag dev_alias_add: [auto: :ds]
    test "changes ttl of an immutable via name", ctx do
      assert %{dev_alias: %{name: name, nature: nature}} = ctx

      ttl_ms = 60_000
      dev_alias = Sally.DevAlias.ttl_adjust(name, ttl_ms)

      assert %{name: ^name, nature: ^nature, ttl_ms: ^ttl_ms} = dev_alias
      assert %{seen_at: %DateTime{}} = dev_alias
    end

    @tag dev_alias_add: [auto: :pwm]
    test "changes ttl of a mutable via id", ctx do
      assert %{dev_alias: %{id: id, nature: nature}} = ctx

      ttl_ms = 60_000
      dev_alias = Sally.DevAlias.ttl_adjust(id, ttl_ms)

      assert %{id: ^id, nature: ^nature, ttl_ms: ^ttl_ms} = dev_alias
      assert %{seen_at: %DateTime{}} = dev_alias
    end
  end

  describe "Sally.DevAlias.reset/2" do
    @tag dev_alias_add: [auto: :ds]
    test "sets updated_at using a nature schema", ctx do
      assert %{dev_alias: %{id: id, nature: nature}} = ctx

      fake_nature_schema = %{dev_alias_id: id}
      now = Timex.now()

      dev_alias = Sally.DevAlias.ttl_reset(fake_nature_schema, now)

      assert %{id: ^id, nature: ^nature} = dev_alias
      assert %{seen_at: ^now, updated_at: ^now} = dev_alias
    end

    @tag dev_alias_add: [auto: :pwm]
    test "sets updated_at using a DevAlias", ctx do
      assert %{dev_alias: %{id: id, nature: nature} = dev_alias} = ctx

      now = Timex.now()
      dev_alias = Sally.DevAlias.ttl_reset(dev_alias, now)

      assert %{id: ^id, nature: ^nature} = dev_alias
      assert %{seen_at: ^now, updated_at: ^now} = dev_alias
    end
  end
end
