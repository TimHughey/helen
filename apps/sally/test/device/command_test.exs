defmodule SallyCommandTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_command: true

  setup [:dev_alias_add]

  describe "Sally.Command.broom_timeout/1" do
    @tag dev_alias_add: [auto: :mcp23008, cmds: [history: 2, latest: :busy]]
    test "acks a command", ctx do
      assert %{dev_alias: dev_alias, cmd_latest: cmd} = ctx

      assert %Sally.DevAlias{id: dev_alias_id} = dev_alias
      assert %Sally.Command{acked: false, refid: refid} = cmd

      {:error, {:already_started, _pid}} = Sally.Command.track(cmd, [])

      tracked_info = Sally.Command.tracked_info(refid)
      assert %Sally.Command{} = tracked_info

      broom = %Alfred.Broom{tracked_info: tracked_info}

      assert {:ok, %Sally.Command{} = cmd} = Sally.Command.broom_timeout(broom)

      assert %{acked: true, orphaned: true} = cmd
      assert %{acked_at: %DateTime{}, rt_latency_us: rt_us} = cmd
      assert %{dev_alias_id: ^dev_alias_id} = cmd

      assert is_integer(rt_us) and rt_us > 100
    end
  end

  describe "Sally.Command.save/1" do
    @tag dev_alias_add: [auto: :pwm, cmds: [history: 2, latest: :busy]]
    test "replaces the command for a Sally.DevAlias", ctx do
      assert %{cmd_latest: %Sally.Command{acked: false, refid: refid} = cmd} = ctx
      assert %{dev_alias: %Sally.DevAlias{} = dev_alias} = ctx
      assert %Sally.Command{acked: false} = Sally.Command.save(cmd)
      assert Sally.Command.busy?(cmd)
      assert Sally.Command.busy(dev_alias)
      assert Sally.Command.busy?(refid)

      acked_cmd = Sally.Command.ack_now(cmd)
      assert %Sally.Command{acked: true, acked_at: %DateTime{}} = acked_cmd

      refute Sally.Command.busy?(dev_alias)
      assert %Sally.Command{acked: true} = Sally.Command.saved(dev_alias)
    end
  end

  describe "Sally.Command.saved_count/0" do
    @tag dev_alias_add: [auto: :pwm, count: 3, cmds: [history: 2, latest: :busy]]
    test "increaases", _ctx do
      assert Sally.Command.saved_count() >= 3
    end
  end
end
