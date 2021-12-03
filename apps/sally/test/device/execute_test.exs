defmodule SallyExecuteTest do
  use ExUnit.Case, async: true
  use Should
  use Sally.TestAid

  @moduletag sally: true, sally_execute: true

  alias Alfred.{ExecCmd, ExecResult}
  alias Sally.Execute

  setup_all do
    # always create and setup a host
    {:ok, %{host_add: [], host_setup: []}}
  end

  setup [:host_add, :host_setup, :device_add, :devalias_add, :command_add]

  describe "Sally.Execute.cmd/2" do
    @tag device_add: [auto: :mcp23008], devalias_add: []
    test "executes an 'on' ExecCmd", ctx do
      name = ctx.dev_alias.name
      er = %ExecCmd{name: name, cmd: "on"} |> Execute.cmd()

      want_kv = [cmd: "on", name: name, rc: :ok, will_notify_when_released: false]
      Should.Be.Struct.with_all_key_value(er, ExecResult, want_kv)
      Should.Be.binary(er.refid)
      Should.Be.asserted(fn -> er.track_timeout_ms > 0 end)
    end

    @tag device_add: [auto: :pwm], devalias_add: []
    test "executes a custom cmd and immediately acks", ctx do
      name = ctx.dev_alias.name
      cmd_opts = [ack: :immediate, notify_when_released: true]
      cmd_params = %{type: "test", p1: "ack"}
      er = %ExecCmd{name: name, cmd: "immediate", cmd_opts: cmd_opts, cmd_params: cmd_params} |> Execute.cmd()

      want_kv = [cmd: "immediate", name: name, rc: :ok, will_notify_when_released: true]
      Should.Be.Struct.with_all_key_value(er, ExecResult, want_kv)

      receive do
        {Broom, te} ->
          want_kv = [refid: er.refid, acked: true, orphaned: false]
          Should.Be.Struct.with_all_key_value(te, Broom.TrackerEntry, want_kv)
      after
        100 ->
          assert :timeout == true, Should.msg(:timeout, "should have received", Broom.TrackerEntry)
      end
    end

    @tag device_add: [auto: :pwm], devalias_add: []
    @tag command_add: [cmd: "on"]
    test "detects same cmd is active", ctx do
      name = ctx.dev_alias.name
      er = %ExecCmd{name: name, cmd: "on"} |> Execute.cmd()

      want_kv = [cmd: "on", name: name, rc: :ok, will_notify_when_released: false]
      Should.Be.Struct.with_all_key_value(er, ExecResult, want_kv)
      Should.Be.asserted(fn -> is_nil(er.refid) end)
      Should.Be.asserted(fn -> er.track_timeout_ms > 0 end)
    end
  end

  describe "Sally.Execute.track_timeout/1" do
    @tag device_add: [auto: :pwm], devalias_add: []
    @tag command_add: [cmd: "off"]
    test "processes a track timeout and orphans a command", ctx do
      name = ctx.dev_alias.name
      cmd_opts = [track_timeout_ms: 1, notify_when_released: true]
      er = %ExecCmd{name: name, cmd: "orphan", cmd_opts: cmd_opts} |> Execute.cmd()

      want_kv = [cmd: "orphan", name: name, rc: :ok, will_notify_when_released: true]
      Should.Be.Struct.with_all_key_value(er, ExecResult, want_kv)
      Should.Be.binary(er.refid)
      Should.Be.asserted(fn -> er.track_timeout_ms > 0 end)

      receive do
        {Broom, te} ->
          want_kv = [refid: er.refid, acked: true, orphaned: true]
          Should.Be.Struct.with_all_key_value(te, Broom.TrackerEntry, want_kv)
      after
        100 ->
          assert :timeout == true, Should.msg(:timeout, "should have received", Broom.TrackerEntry)
      end
    end
  end

  describe "Sally.Execute.tracked_counts" do
    alias Broom.Counts

    test "/0 returns current counts" do
      Execute.tracked_counts() |> Should.Be.struct(Counts)
    end

    test "_reset/1 resets :orphaned and :errors by default" do
      Execute.tracked_counts_reset() |> Should.Be.Tuple.with_rc_and_struct(:reset, Counts)
    end
  end
end
