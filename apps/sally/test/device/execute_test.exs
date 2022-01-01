defmodule SallyExecuteTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_execute: true

  setup_all do
    # always create and setup a host
    {:ok, %{host_add: [], host_setup: []}}
  end

  setup [:host_add, :host_setup, :device_add, :devalias_add, :command_add]

  describe "Sally.Execute.cmd/2" do
    @tag device_add: [auto: :mcp23008], devalias_add: []
    test "executes an 'on' ExecCmd", ctx do
      name = ctx.dev_alias.name
      er = %Alfred.ExecCmd{name: name, cmd: "on"} |> Sally.Execute.cmd()

      assert %Alfred.ExecResult{
               cmd: "on",
               name: ^name,
               rc: :ok,
               will_notify_when_released: false,
               refid: <<_::binary>>,
               track_timeout_ms: timeout_ms
             } = er

      assert timeout_ms > 0
    end

    @tag device_add: [auto: :pwm], devalias_add: []
    test "executes a custom cmd and immediately acks", ctx do
      name = ctx.dev_alias.name
      cmd_opts = [ack: :immediate, notify_when_released: true]
      cmd_params = %{type: "test", p1: "ack"}

      ec = %Alfred.ExecCmd{name: name, cmd: "immediate", cmd_opts: cmd_opts, cmd_params: cmd_params}
      er = Sally.Execute.cmd(ec)

      assert %Alfred.ExecResult{
               cmd: "immediate",
               name: ^name,
               rc: :ok,
               will_notify_when_released: true,
               refid: refid
             } = er

      assert_receive {Broom, %Broom.TrackerEntry{refid: ^refid, acked: true, orphaned: false}}, 100
    end

    @tag device_add: [auto: :pwm], devalias_add: []
    @tag command_add: [cmd: "on"]
    test "detects same cmd is active", ctx do
      name = ctx.dev_alias.name
      er = %Alfred.ExecCmd{name: name, cmd: "on"} |> Sally.Execute.cmd()

      assert %Alfred.ExecResult{
               cmd: "on",
               name: ^name,
               rc: :ok,
               will_notify_when_released: false,
               refid: nil,
               track_timeout_ms: timeout_ms
             } = er

      assert timeout_ms > 0
    end
  end

  describe "Sally.Execute.track_timeout/1" do
    @tag device_add: [auto: :pwm], devalias_add: []
    @tag command_add: [cmd: "off"]
    test "processes a track timeout and orphans a command", ctx do
      name = ctx.dev_alias.name
      cmd_opts = [track_timeout_ms: 1, notify_when_released: true]
      ec = %Alfred.ExecCmd{name: name, cmd: "orphan", cmd_opts: cmd_opts}
      er = Sally.Execute.cmd(ec)

      assert %Alfred.ExecResult{
               cmd: "orphan",
               name: ^name,
               rc: :ok,
               will_notify_when_released: true,
               refid: refid
             } = er

      assert_receive {Broom, %Broom.TrackerEntry{refid: ^refid, acked: true, orphaned: true}}, 100
    end
  end

  describe "Sally.Execute.tracked_counts" do
    test "/0 returns current counts" do
      assert %Broom.Counts{} = Sally.Execute.tracked_counts()
    end

    test "_reset/1 resets :orphaned and :errors by default" do
      assert {:reset, %Broom.Counts{}} = Sally.Execute.tracked_counts_reset()
    end
  end
end
