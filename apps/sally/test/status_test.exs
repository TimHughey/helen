defmodule SallyStatusTest do
  use ExUnit.Case, async: true
  use Should

  @host_ident_default "sally.hoststatus0"
  @host_name_default "Sally Status Test"
  @moduletag sally_status: true

  alias Alfred.MutableStatus
  alias Sally.Test.Support

  setup_all ctx do
    ctx
  end

  # setup [:setup_wrapped]

  test "can Sally.status/3 detect unknown Alias name", _ctx do
    res = Sally.status(:mutable, "unknown", [])
    should_be_struct(res, MutableStatus)

    fail = pretty("Status result did not match", res)
    assert res.name == "unknown", fail
    refute res.found?, fail
    assert res.cmd == "unknown", fail
    assert res.pending? == false, fail
    assert res.pending_refid |> is_nil(), fail
    refute res.ttl_expired?, fail
  end

  @tag dev_alias_opts: [name: "Status TTL Test WITH OPTS", pio: 0]
  @tag status_opts: [ttl_ms: 0]
  test "can Sally.status/3 detect ttl expired with ttl_ms opt", ctx do
    host_opts = [ident: @host_ident_default, name: @host_name_default]
    device_opts = [ident: "status_test01", family: "ds", mutable: false]

    device = Support.add_host(host_opts) |> Support.add_device(device_opts)
    dev_alias = Sally.DevAlias.create!(device, ctx.dev_alias_opts)
    should_be_schema(dev_alias, Sally.DevAlias)

    res = Sally.status(:mutable, dev_alias.name, ctx.status_opts)
    should_be_struct(res, MutableStatus)

    fail = pretty("Status result did not match", res)
    assert res.name == dev_alias.name, fail
    assert res.found?, fail
    assert res.ttl_expired?, fail
  end

  @tag host_opts: [host: @host_ident_default, name: @host_name_default]
  @tag device_opts: [device: "status_test02", family: "i2c", mutable: true]
  @tag dev_alias_opts: [name: "Status TTL Test NO OPTS", ttl_ms: 50, pio: 1]
  test "can Sally.status/3 detect ttl expired based on Alias ttl_ms", ctx do
    device = Support.add_host(ctx.host_opts) |> Support.add_device(ctx.device_opts)

    dev_alias = Sally.DevAlias.create!(device, ctx.dev_alias_opts)

    should_be_schema(dev_alias, Sally.DevAlias)

    # allow dev alias TTL to elapsed
    Process.sleep(51)

    res = Sally.status(:mutable, dev_alias.name, [])
    should_be_struct(res, MutableStatus)

    fail = pretty("Status result did not match", res)
    assert res.name == dev_alias.name, fail
    assert res.found?, fail
    assert res.ttl_expired?, fail
  end

  @tag host_opts: [host: @host_ident_default, name: @host_name_default]
  @tag device_opts: [device: "status_test03", family: "pwm", mutable: true]
  @tag dev_alias_opts: [name: "Status Pending Test", ttl_ms: 1000, pio: 2]
  @tag cmd: "pending"
  test "can Sally.status/3 detect pending Alias cmd", ctx do
    device = Support.add_host(ctx.host_opts) |> Support.add_device(ctx.device_opts)
    dev_alias = Sally.DevAlias.create!(device, ctx.dev_alias_opts)
    should_be_schema(dev_alias, Sally.DevAlias)

    cmd = Support.add_command(dev_alias, ctx.cmd)
    should_be_schema(cmd, Sally.Command)

    res = Sally.status(:mutable, dev_alias.name, [])
    should_be_struct(res, MutableStatus)

    fail = pretty("Status result did not match", res)
    assert res.name == dev_alias.name, fail
    assert res.found?, fail
    assert res.cmd == "pending", fail
    refute res.ttl_expired?, fail
    assert res.pending?, fail
    refute res.pending_refid |> is_nil(), fail
    assert res.error == :none, fail
  end

  @tag host_opts: [host: @host_ident_default, name: @host_name_default]
  @tag device_opts: [device: "status_test03", family: "pwm", mutable: true]
  @tag dev_alias_opts: [name: "Status Unresponsive Test", ttl_ms: 1000, pio: 3]
  @tag cmd: "unresponsive"
  @tag cmd_disposition: :orphan
  test "can Sally.status/3 detect unresponsive Alias (orphaned cmd)", ctx do
    device = Support.add_host(ctx.host_opts) |> Support.add_device(ctx.device_opts)
    dev_alias = Sally.DevAlias.create!(device, ctx.dev_alias_opts)
    should_be_schema(dev_alias, Sally.DevAlias)

    cmd = Support.add_command(dev_alias, ctx.cmd)
    should_be_schema(cmd, Sally.Command)

    acked_cmd = Sally.Command.ack_now(cmd, ctx.cmd_disposition, DateTime.utc_now())
    should_be_schema(acked_cmd, Sally.Command)

    res = Sally.status(:mutable, dev_alias.name, [])
    should_be_struct(res, MutableStatus)

    fail = pretty("Status result did not match", res)
    assert res.name == dev_alias.name, fail
    assert res.found?, fail
    assert res.cmd == "unknown", fail
    refute res.ttl_expired?, fail
    refute res.pending?, fail
    assert res.pending_refid |> is_nil(), fail
    assert res.error == :unresponsive, fail
  end

  @tag host_opts: [host: @host_ident_default, name: @host_name_default]
  @tag device_opts: [device: "status_test03", family: "pwm", mutable: true]
  @tag dev_alias_opts: [name: "Status Good Test", ttl_ms: 1000, pio: 4]
  @tag cmd: "good"
  @tag cmd_disposition: :ack
  test "can Sally.status/3 detect good status", ctx do
    device = Support.add_host(ctx.host_opts) |> Support.add_device(ctx.device_opts)
    dev_alias = Sally.DevAlias.create!(device, ctx.dev_alias_opts)
    should_be_schema(dev_alias, Sally.DevAlias)

    cmd = Support.add_command(dev_alias, ctx.cmd)
    should_be_schema(cmd, Sally.Command)

    acked_cmd = Sally.Command.ack_now(cmd, ctx.cmd_disposition, DateTime.utc_now())
    should_be_schema(acked_cmd, Sally.Command)

    res = Sally.status(:mutable, dev_alias.name, [])
    should_be_struct(res, MutableStatus)

    fail = pretty("Status result did not match", res)
    assert res.name == dev_alias.name, fail
    assert res.found?, fail
    assert res.cmd == "good", fail
    refute res.ttl_expired?, fail
    refute res.pending?, fail
    assert res.pending_refid |> is_nil(), fail
    assert res.error == :none, fail
  end
end
