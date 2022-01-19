defmodule Sally.MutableHandlerTest do
  use ExUnit.Case, async: true
  use Sally.TestAid
  require Sally.DispatchAid

  @moduletag sally: true, sally_mutable_handler: true

  setup_all do
    # always create and setup a host
    {:ok, %{host_add: [], host_setup: []}}
  end

  setup [:host_add, :host_setup, :device_add, :devalias_add, :command_add, :dispatch_add]

  describe "Sally.Mutable.Handler.db_actions/1 processes a" do
    @tag device_add: [auto: :mcp23008], devalias_add: []
    @tag dispatch_add: [subsystem: "mut", category: "status"]
    test "well-formed status Sally.Dispatch with one DevAlias", ctx do
      assert %Sally.Dispatch{txn_info: txn_info} = ctx[:dispatch]

      assert %{
               aliases: [%Sally.DevAlias{id: dev_alias_id, name: name, device_id: device_id} | _],
               aligned_0: %Sally.Command{dev_alias_id: dev_alias_id, cmd: "on"},
               device: %Sally.Device{id: device_id, family: "i2c", mutable: true}
             } = txn_info

      # NOTE: confirm the name is registered
      assert %{name: ^name, nature: :cmds} = Alfred.name_info(name)
    end

    @tag device_add: [auto: :mcp23008], devalias_add: [count: 5]
    @tag dispatch_add: [subsystem: "mut", category: "status"]
    test "well-formed Sally.Dispatch with multiple DevAlias", ctx do
      assert %Sally.Dispatch{txn_info: txn_info} = ctx[:dispatch]

      assert %{
               aliases: aliases,
               device: %Sally.Device{family: "i2c", mutable: true}
             } = txn_info

      assert length(aliases) == 5

      Enum.all?(0..4, fn pio ->
        aligned_key = String.to_atom("aligned_#{pio}")
        assert is_map_key(txn_info, aligned_key)
        assert %Sally.Command{} = Map.get(txn_info, aligned_key)
      end)
    end
  end

  describe "Sally.Mutable.Handler.db_cmd_ack/2 processes a" do
    @tag device_add: [auto: :mcp23008], devalias_add: []
    @tag dispatch_add: [subsystem: "mut", category: "cmdack"]
    test "well formed Sally.Dispatch", ctx do
      assert %Sally.DevAlias{id: dev_alias_id} = ctx[:dev_alias]
      assert %Sally.Dispatch{txn_info: txn_info} = ctx[:dispatch]

      assert %{
               aliases: %Sally.DevAlias{id: ^dev_alias_id},
               command: %Sally.Command{dev_alias_id: ^dev_alias_id, id: cmd_id, refid: refid},
               cmd_to_ack: %Sally.Command{acked: false, id: cmd_id},
               device: %Sally.Device{}
             } = txn_info

      assert :not_tracked == Sally.Command.tracked_info(refid)
    end
  end

  describe "Sally.Mutable.Handler.process/1" do
    @tag device_add: [auto: :mcp23008], devalias_add: []
    @tag dispatch_add: [subsystem: "mut", category: "cmdack"]
    test "handles a cmdack Dispatch", ctx do
      assert %Sally.Dispatch{txn_info: %{}} = dispatch = ctx.dispatch

      Sally.DispatchAid.assert_processed(dispatch)
    end

    @tag device_add: [auto: :mcp23008], devalias_add: []
    @tag command_add: []
    @tag dispatch_add: [subsystem: "mut", category: "status"]
    test "handles a status Dispatch", ctx do
      assert %Sally.Dispatch{txn_info: %{}} = dispatch = ctx.dispatch

      Sally.DispatchAid.assert_processed(dispatch)
    end
  end
end
