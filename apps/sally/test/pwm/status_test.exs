defmodule SallyPwmStatusTest do
  use ExUnit.Case
  use Should

  @device_ident_default "status"
  @device_host_default "sally.test-status"
  @defaults [device_opts: [host: @device_host_default, ident: @device_ident_default]]

  @moduletag pwm_status: true, defaults: @defaults

  alias Alfred.MutableStatus
  alias Sally.PulseWidth.Status

  setup_all ctx do
    ctx
  end

  setup [:setup_wrapped]

  test "can PulseWidth.Status.get/2 detect unknown Alias name", _ctx do
    res = Status.get("unknown", [])
    should_be_struct(res, MutableStatus)

    fail = pretty("Status result did not match", res)
    assert res.name == "unknown", fail
    refute res.found?, fail
    assert res.cmd == "unknown", fail
    assert res.pending? == false, fail
    assert res.pending_refid |> is_nil(), fail
    refute res.ttl_expired?, fail
  end

  @tag alias_opts: [name: "Status TTL Test WITH OPTS", pio: 0]
  @tag status_opts: [ttl_ms: 0]
  @tag cmd: "basic"
  test "can PulseWidth.Status.get/2 detect ttl expired with ttl_ms opt", ctx do
    alias_name = ctx.ts.dev_alias.name

    res = Status.get(alias_name, ctx.status_opts)
    should_be_struct(res, MutableStatus)

    fail = pretty("Status result did not match", res)
    assert res.name == alias_name, fail
    assert res.found?, fail
    assert res.ttl_expired?, fail
  end

  @tag alias_opts: [name: "Status TTL Test NO OPTS", ttl_ms: 50, pio: 1]
  test "can PulseWidth.Status.get/2 detect ttl expired based on Alias ttl_ms", ctx do
    # allow dev alias TTL to elapsed
    Process.sleep(51)

    alias_name = ctx.ts.dev_alias.name

    res = Status.get(alias_name, [])
    should_be_struct(res, MutableStatus)

    fail = pretty("Status result did not match", res)
    assert res.name == alias_name, fail
    assert res.found?, fail
    assert res.ttl_expired?, fail
  end

  @tag alias_opts: [name: "Status Pending Test", ttl_ms: 1000, pio: 2]
  @tag cmd: "pending"
  test "can PulseWidth.Status.get/2 detect pending Alias cmd", ctx do
    alias_name = ctx.ts.dev_alias.name

    res = Status.get(alias_name, [])
    should_be_struct(res, MutableStatus)

    fail = pretty("Status result did not match", res)
    assert res.name == alias_name, fail
    assert res.found?, fail
    assert res.cmd == "pending", fail
    refute res.ttl_expired?, fail
    assert res.pending?, fail
    refute res.pending_refid |> is_nil(), fail
    assert res.error == :none, fail
  end

  @tag alias_opts: [name: "Status Unresponsive Test", ttl_ms: 1000, pio: 3]
  @tag cmd: "unresponsive"
  @tag cmd_disposition: :orphan
  test "can PulseWidth.Status.get/2 detect unresponsive Alias (orphaned cmd)", ctx do
    alias_name = ctx.ts.dev_alias.name

    res = Status.get(alias_name, [])
    should_be_struct(res, MutableStatus)

    fail = pretty("Status result did not match", res)
    assert res.name == alias_name, fail
    assert res.found?, fail
    assert res.cmd == "unknown", fail
    refute res.ttl_expired?, fail
    refute res.pending?, fail
    assert res.pending_refid |> is_nil(), fail
    assert res.error == :unresponsive, fail
  end

  @tag alias_opts: [name: "Status Good Test", ttl_ms: 1000, pio: 4]
  @tag cmd: "good"
  @tag cmd_disposition: :ack
  test "can PulseWidth.Status.get/2 detect good status", ctx do
    alias Sally.PulseWidth.DB.Alias

    dev_alias = ctx.ts.dev_alias
    alias_name = dev_alias.name

    # update the alias
    dev_alias.id |> Alias.update_cmd(ctx.cmd)

    res = Status.get(alias_name, [])
    should_be_struct(res, MutableStatus)

    fail = pretty("Status result did not match", res)
    assert res.name == alias_name, fail
    assert res.found?, fail
    assert res.cmd == "good", fail
    refute res.ttl_expired?, fail
    refute res.pending?, fail
    assert res.pending_refid |> is_nil(), fail
    assert res.error == :none, fail
  end

  defp setup_cmd(%{cmd: cmd, ts: ts} = ctx) when is_binary(cmd) do
    alias Sally.PulseWidth.DB.Command

    put_added_cmd = fn x -> put_in(ctx, [:added_cmd], x) end

    cmd_opts = ctx[:cmd_opts] || []
    cmd_disposition = ctx[:cmd_disposition]

    new_cmd = Command.add(ts.dev_alias, cmd, cmd_opts)

    if cmd_disposition do
      Command.ack_now(new_cmd, cmd_disposition, DateTime.utc_now()) |> put_added_cmd.()
    else
      new_cmd |> put_added_cmd.()
    end
  end

  defp setup_cmd(ctx), do: ctx

  defp setup_wrapped(ctx) do
    alias Sally.PulseWidth.TestSupport, as: TS
    alias Sally.Repo

    txn_res =
      Repo.transaction(fn ->
        Repo.checkout(fn ->
          ctx |> TS.init() |> TS.ensure_device() |> TS.create_alias() |> setup_cmd()
        end)
      end)

    fail = pretty("txn failed", txn_res)
    assert elem(txn_res, 0) == :ok, fail

    elem(txn_res, 1)
  end
end
