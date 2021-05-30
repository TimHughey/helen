defmodule SallyPwmExecuteTest do
  use ExUnit.Case
  use Should

  @device_ident_default "pwm/sally-execute"
  @device_host_default "pwm.sally-execute"
  @defaults [device_opts: [host: @device_host_default, ident: @device_ident_default]]

  @moduletag pwm_execute: true, defaults: @defaults

  alias Alfred.{ExecCmd, ExecResult}
  alias Sally.PulseWidth.Execute
  alias Sally.PulseWidth.TestSupport, as: TS

  setup_all ctx do
    ctx
  end

  setup [:setup_wrapped]

  describe "can PulseWidth.Execute.cmd/1 detect specified cmd is not a" do
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

  test "can PulseWidth.Execute.cmd/1 detect an Alias name does not exist" do
    res = %ExecCmd{name: "foobar", cmd: "on"} |> Execute.cmd()
    should_be_struct(res, ExecResult)

    fail = pretty("ExecResult did not match", res)
    assert res.name == "foobar", fail
    assert res.rc == :not_found, fail
    assert res.cmd == "unknown", fail
  end

  @tag alias_opts: [name: "Execute TTL Expired", pio: 0]
  test "can PulseWidth.Execute.cmd/1 detect ttl expired", ctx do
    Process.sleep(10)

    res = %ExecCmd{name: ctx.alias_opts[:name], cmd: "on", cmd_opts: [ttl_ms: 0]} |> Execute.cmd()
    should_be_struct(res, ExecResult)

    fail = pretty("ExecResult did not match", res)
    assert res.cmd == "unknown", fail
    assert res.name == ctx.alias_opts[:name], fail
    assert should_be_tuple(res.rc)
    assert elem(res.rc, 0) == :ttl_expired, fail
    assert elem(res.rc, 1) > 0, fail
    assert res.refid |> is_nil(), fail
    assert res.track_timeout_ms |> is_nil(), fail
    refute res.will_notify_when_released, fail
  end

  @tag alias_opts: [name: "Execute Nominal Case", pio: 1]
  test "can PulseWidth.Execute.cmd/1 execute an 'on' ExecCmd", ctx do
    res = %ExecCmd{name: ctx.alias_opts[:name], cmd: "on"} |> Execute.cmd()
    should_be_struct(res, ExecResult)

    fail = pretty("ExecResult did not match", res)
    assert res.cmd == "on", fail
    assert res.name == ctx.alias_opts[:name], fail
    assert res.rc == :ok, fail
    refute res.refid |> is_nil(), fail
    assert res.track_timeout_ms > 0, fail
    refute res.will_notify_when_released, fail
  end

  @tag alias_opts: [name: "Execute Ack Immediate", pio: 2]
  test "can PulseWidth.Execute.cmd/1 and ack immediate", ctx do
    alias_name = ctx.alias_opts[:name]

    cmd_opts = [ack: :immediate, notify_when_released: true]
    cmd_params = %{type: "test", p1: "ack"}
    ec = %ExecCmd{name: alias_name, cmd: "immediate", cmd_opts: cmd_opts, cmd_params: cmd_params}

    res = Execute.cmd(ec)
    should_be_struct(res, ExecResult)

    fail = pretty("ExecResult did not match", res)
    assert res.cmd == ec.cmd, fail
    assert res.name == ctx.alias_opts[:name], fail
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

  @tag alias_opts: [name: "Execute Orphan", pio: 3]
  test "can PulseWidth.Execute process Broom track timeouts and orphan a command", ctx do
    alias_name = ctx.alias_opts[:name]

    cmd_opts = [track_timeout_ms: 1, notify_when_released: true]
    cmd_params = %{type: "test", p1: "orphan"}
    ec = %ExecCmd{name: alias_name, cmd: "orphan", cmd_opts: cmd_opts, cmd_params: cmd_params}

    res = Execute.cmd(ec)
    should_be_struct(res, ExecResult)

    fail = pretty("ExecResult did not match", res)
    assert res.cmd == ec.cmd, fail
    assert res.name == ctx.alias_opts[:name], fail
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

  @tag alias_opts: [name: "Duplicate Cmd", pio: 4]
  test "can PulseWidth.Execute.cmd/1 detect same cmd is active", ctx do
    alias_name = ctx.alias_opts[:name]

    cmd_opts = [ack: :immediate, notify_when_released: true]
    cmd_params = %{type: "test", p1: "duplicate"}
    ec = %ExecCmd{name: alias_name, cmd: "same cmd", cmd_opts: cmd_opts, cmd_params: cmd_params}

    res = Execute.cmd(ec)
    should_be_struct(res, ExecResult)

    fail = pretty("ExecResult did not match", res)
    assert res.cmd == ec.cmd, fail
    assert res.name == ctx.alias_opts[:name], fail
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
    ec = %ExecCmd{name: alias_name, cmd: "same cmd", cmd_opts: cmd_opts, cmd_params: cmd_params}

    dup = Execute.cmd(ec)
    should_be_struct(dup, ExecResult)

    fail = pretty("ExecResult did not match", dup)
    assert dup.cmd == ec.cmd, fail
    assert dup.name == ctx.alias_opts[:name], fail
    assert dup.rc == :ok, fail
    assert dup.refid |> is_nil(), fail
    assert dup.track_timeout_ms |> is_nil(), fail
    refute dup.will_notify_when_released, fail
  end

  defp setup_wrapped(ctx) do
    alias Sally.PulseWidth.TestSupport, as: TS
    alias SallyRepo, as: Repo

    txn_res =
      Repo.transaction(fn ->
        Repo.checkout(fn ->
          ctx |> TS.init() |> TS.ensure_device() |> TS.create_alias()
        end)
      end)

    # allow DB commit to complete
    Process.sleep(10)

    fail = pretty("txn failed", txn_res)
    assert elem(txn_res, 0) == :ok, fail

    elem(txn_res, 1)
  end
end
