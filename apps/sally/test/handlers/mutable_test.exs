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
    test "well-formed Sally.Dispatch with one DevAlias", ctx do
      assert %Sally.Dispatch{} = dispatch = ctx[:dispatch]

      assert {:ok,
              %{
                aliases: [%Sally.DevAlias{id: dev_alias_id, device_id: device_id} | _],
                aligned_0: %Sally.Command{dev_alias_id: dev_alias_id, cmd: "on"},
                device: %Sally.Device{id: device_id, family: "i2c", mutable: true}
                # seen_list: [%Sally.DevAlias{id: dev_alias_id, device_id: device_id} | _]
              }} = Sally.Mutable.Handler.db_actions(dispatch)
    end

    @tag device_add: [auto: :mcp23008], devalias_add: [count: 5]
    @tag dispatch_add: [subsystem: "mut", category: "status"]
    test "well-formed Sally.Dispatch with multiple DevAlias", ctx do
      assert %Sally.Dispatch{} = dispatch = ctx[:dispatch]

      assert {:ok,
              %{
                aliases: aliases,
                device: %Sally.Device{family: "i2c", mutable: true}
                # seen_list: seen_list
              } = db_multi_result} = Sally.Mutable.Handler.db_actions(dispatch)

      assert length(aliases) == 5
      # assert length(seen_list) == 5

      Enum.all?(0..4, fn pio ->
        aligned_key = String.to_atom("aligned_#{pio}")
        assert is_map_key(db_multi_result, aligned_key)
        assert %Sally.Command{} = Map.get(db_multi_result, aligned_key)
      end)
    end
  end

  describe "Sally.Mutable.Handler.db_cmd_ack/2 processes a" do
    @tag device_add: [auto: :mcp23008], devalias_add: []
    @tag command_add: [cmd: "on"]
    @tag dispatch_add: [subsystem: "mut", category: "cmdack"]
    test "well formed Sally.Dispatch", ctx do
      assert %Sally.DevAlias{} = ctx[:dev_alias]
      assert %Sally.Command{id: command_id} = command = ctx[:command]
      assert %Sally.Dispatch{} = dispatch = ctx[:dispatch]

      assert {:ok,
              %{
                command: %Sally.Command{id: ^command_id},
                device: %Sally.Device{},
                aliases: %Sally.DevAlias{}
              }} = Sally.Mutable.Handler.db_cmd_ack(dispatch, command)
    end
  end

  describe "Sally.Mutable.Handler.process/1" do
    @tag device_add: [auto: :mcp23008], devalias_add: []
    @tag command_add: [cmd: "on", track: true]
    @tag dispatch_add: [subsystem: "mut", category: "cmdack"]
    test "handles a cmdack Dispatch", ctx do
      assert %Sally.Dispatch{} = dispatch = ctx[:dispatch]

      dispatch
      |> Sally.Mutable.Handler.process()
      |> Sally.DispatchAid.assert_processed()
    end

    @tag device_add: [auto: :mcp23008], devalias_add: []
    @tag command_add: []
    @tag dispatch_add: [subsystem: "mut", category: "status"]
    test "handles a status Dispatch", ctx do
      assert %Sally.Dispatch{} = dispatch = ctx[:dispatch]

      dispatch
      |> Sally.Mutable.Handler.process()
      |> Sally.DispatchAid.assert_processed()
    end
  end
end
