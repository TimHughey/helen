defmodule SallyCommandTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_command: true

  setup [:dev_alias_add]

  describe "Sally.Command.broom_timeout/1" do
    @tag dev_alias_add: [auto: :mcp23008, cmds: [history: 1, latest: :pending]]
    test "acks a command", ctx do
      assert %{dev_alias: dev_alias, cmd_latest: [execute]} = ctx

      assert %Sally.DevAlias{id: dev_alias_id} = dev_alias
      assert %Alfred.Execute{rc: :pending, detail: %{} = detail} = execute
      assert %{__execute__: %{dev_alias_id: ^dev_alias_id, refid: refid}} = detail
      assert %{__track__: {:ok, broom_pid}} = detail
      assert is_pid(broom_pid)

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
end
