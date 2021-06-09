defmodule SallyPwmExecuteTest do
  use ExUnit.Case, async: true
  use Should

  @host_ident_default "sally.hostexecute0"
  @host_name_default "Sally Execute Test"
  @moduletag sally_execute: true

  alias Alfred.{ExecCmd, ExecResult}
  alias Sally.Execute
  alias Sally.Test.Support

  setup_all ctx do
    ctx
  end

  describe "can Sally.Execute.cmd/1 detect specified cmd is not a" do
    # do not create an Alias, cmd validation occurs before finding the Alias

    test "binary" do
      res = %ExecCmd{cmd: :atoms_not_supported} |> Execute.cmd()

      should_be_struct(res, ExecResult)
      fail = pretty("ExecResult rc did not match", res)
      assert {:invalid, "cmd must be a binary"} == res.rc, fail
    end

    test "simple on/off" do
      res = %ExecCmd{cmd: "special"} |> Execute.cmd()

      should_be_struct(res, ExecResult)
      fail = pretty("ExecResult rc did not match", res)
      assert {:invalid, "custom cmds must include type"} == res.rc, fail
    end
  end

  test "can Sally.Execute.cmd/1 detect an Alias name does not exist" do
    res = %ExecCmd{name: "foobar", cmd: "on"} |> Execute.cmd()
    should_be_struct(res, ExecResult)

    fail = pretty("ExecResult did not match", res)
    assert res.name == "foobar", fail
    assert res.rc == :not_found, fail
    assert res.cmd == "unknown", fail
  end

  @tag host_opts: [host: @host_ident_default, name: @host_name_default]
  @tag device_opts: [device: "execute_test01", family: "pwm", mutable: true]
  @tag dev_alias_opts: [name: "Execute TTL Expired", pio: 0]
  test "can Sally.Execute.cmd/1 detect ttl expired", ctx do
    device = Support.add_host(ctx.host_opts) |> Support.add_device(ctx.device_opts)
    dev_alias = Sally.DevAlias.create(device, ctx.dev_alias_opts)
    should_be_schema(dev_alias, Sally.DevAlias)

    res = %ExecCmd{name: ctx.dev_alias_opts[:name], cmd: "on", cmd_opts: [ttl_ms: 0]} |> Execute.cmd()
    should_be_struct(res, ExecResult)

    fail = pretty("ExecResult did not match", res)
    assert res.cmd == "unknown", fail
    assert res.name == ctx.dev_alias_opts[:name], fail
    assert should_be_tuple(res.rc)
    assert elem(res.rc, 0) == :ttl_expired, fail
    assert elem(res.rc, 1) > 0, fail
    assert res.refid |> is_nil(), fail
    assert res.track_timeout_ms |> is_nil(), fail
    refute res.will_notify_when_released, fail
  end

  @tag host_opts: [host: @host_ident_default, name: @host_name_default]
  @tag device_opts: [device: "execute_test01", family: "pwm", mutable: true]
  @tag dev_alias_opts: [name: "Execute Nominal Case", pio: 1]
  test "can Sally.Execute.cmd/1 execute an 'on' ExecCmd", ctx do
    device = Support.add_host(ctx.host_opts) |> Support.add_device(ctx.device_opts)
    dev_alias = Sally.DevAlias.create(device, ctx.dev_alias_opts)
    should_be_schema(dev_alias, Sally.DevAlias)

    res = %ExecCmd{name: ctx.dev_alias_opts[:name], cmd: "on"} |> Execute.cmd()
    should_be_struct(res, ExecResult)

    fail = pretty("ExecResult did not match", res)
    assert res.cmd == "on", fail
    assert res.name == ctx.dev_alias_opts[:name], fail
    assert res.rc == :ok, fail
    refute res.refid |> is_nil(), fail
    assert res.track_timeout_ms > 0, fail
    refute res.will_notify_when_released, fail
  end

  @tag host_opts: [host: @host_ident_default, name: @host_name_default]
  @tag device_opts: [device: "execute_test01", family: "pwm", mutable: true]
  @tag dev_alias_opts: [name: "Execute Ack Immediate", pio: 2]
  test "can Sally.Execute.cmd/1 and ack immediate", ctx do
    device = Support.add_host(ctx.host_opts) |> Support.add_device(ctx.device_opts)
    dev_alias = Sally.DevAlias.create(device, ctx.dev_alias_opts)
    should_be_schema(dev_alias, Sally.DevAlias)

    cmd_opts = [ack: :immediate, notify_when_released: true]
    cmd_params = %{type: "test", p1: "ack"}
    ec = %ExecCmd{name: dev_alias.name, cmd: "immediate", cmd_opts: cmd_opts, cmd_params: cmd_params}

    res = Execute.cmd(ec)
    should_be_struct(res, ExecResult)

    fail = pretty("ExecResult did not match", res)
    assert res.cmd == ec.cmd, fail
    assert res.name == ctx.dev_alias_opts[:name], fail
    assert res.rc == :ok, fail
    refute res.refid |> is_nil(), fail
    assert res.track_timeout_ms > 0, fail
    assert res.will_notify_when_released, fail

    receive do
      {Broom, :release, %Broom.TrackerEntry{} = te} ->
        fail = pretty("TrackerEntry did not match", te)
        assert te.refid == res.refid, fail
        assert te.acked == true, fail
    after
      100 ->
        fail = pretty("should have received release notification", :timeout)
        assert :timeout == true, fail
    end
  end

  @tag host_opts: [host: @host_ident_default, name: @host_name_default]
  @tag device_opts: [device: "execute_test01", family: "pwm", mutable: true]
  @tag dev_alias_opts: [name: "Execute Orphan", pio: 3]
  test "can Sally.Execute process Broom track timeouts and orphan a command", ctx do
    device = Support.add_host(ctx.host_opts) |> Support.add_device(ctx.device_opts)
    dev_alias = Sally.DevAlias.create(device, ctx.dev_alias_opts)
    should_be_schema(dev_alias, Sally.DevAlias)

    cmd_opts = [track_timeout_ms: 1, notify_when_released: true]
    cmd_params = %{type: "test", p1: "orphan"}
    ec = %ExecCmd{name: dev_alias.name, cmd: "orphan", cmd_opts: cmd_opts, cmd_params: cmd_params}

    res = Execute.cmd(ec)
    should_be_struct(res, ExecResult)

    fail = pretty("ExecResult did not match", res)
    assert res.cmd == ec.cmd, fail
    assert res.name == ctx.dev_alias_opts[:name], fail
    assert res.rc == :ok, fail
    refute res.refid |> is_nil(), fail
    assert res.track_timeout_ms > 0, fail
    assert res.will_notify_when_released, fail

    receive do
      {Broom, :release, %Broom.TrackerEntry{} = te} ->
        fail = pretty("TrackerEntry did not match", te)
        assert te.refid == res.refid, fail
        assert te.acked, fail
        assert te.orphaned, fail
    after
      100 ->
        fail = pretty("should have received release notification", :timeout)
        assert :timeout == true, fail
    end
  end

  @tag host_opts: [host: @host_ident_default, name: @host_name_default]
  @tag device_opts: [device: "execute_test01", family: "pwm", mutable: true]
  @tag dev_alias_opts: [name: "Duplicate Cmd", pio: 4]
  test "can Sally.Execute.cmd/1 detect same cmd is active", ctx do
    device = Support.add_host(ctx.host_opts) |> Support.add_device(ctx.device_opts)
    dev_alias = Sally.DevAlias.create(device, ctx.dev_alias_opts)
    should_be_schema(dev_alias, Sally.DevAlias)

    cmd_opts = [ack: :immediate, notify_when_released: true]
    cmd_params = %{type: "test", p1: "duplicate"}
    ec = %ExecCmd{name: dev_alias.name, cmd: "same cmd", cmd_opts: cmd_opts, cmd_params: cmd_params}

    res = Execute.cmd(ec)
    should_be_struct(res, ExecResult)

    fail = pretty("ExecResult did not match", res)
    assert res.cmd == ec.cmd, fail
    assert res.name == ctx.dev_alias_opts[:name], fail
    assert res.rc == :ok, fail
    refute res.refid |> is_nil(), fail
    assert res.track_timeout_ms > 0, fail
    assert res.will_notify_when_released, fail

    receive do
      {Broom, :release, %Broom.TrackerEntry{} = te} ->
        fail = pretty("TrackerEntry did not match", te)
        assert te.refid == res.refid, fail
        assert te.acked, fail
        refute te.orphaned, fail
    after
      100 ->
        fail = pretty("should have received release notification", :timeout)
        assert :timeout == true, fail
    end

    # now send the exact cmd again without ack immediate or notification
    cmd_opts = []
    cmd_params = %{type: "test", p1: "duplicate"}
    ec = %ExecCmd{name: dev_alias.name, cmd: "same cmd", cmd_opts: cmd_opts, cmd_params: cmd_params}

    dup = Execute.cmd(ec)
    should_be_struct(dup, ExecResult)

    fail = pretty("ExecResult did not match", dup)
    assert dup.cmd == ec.cmd, fail
    assert dup.name == ctx.dev_alias_opts[:name], fail
    assert dup.rc == :ok, fail
    assert dup.refid |> is_nil(), fail
    assert dup.track_timeout_ms |> is_nil(), fail
    refute dup.will_notify_when_released, fail
  end
end
