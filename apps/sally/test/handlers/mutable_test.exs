defmodule Sally.MutableHandlerTest do
  use ExUnit.Case, async: true
  use Should
  use Sally.TestAid

  @moduletag sally: true, sally_mutable_handler: true

  alias Sally.{Command, DevAlias, Device}
  alias Sally.Dispatch
  alias Sally.Mutable.Handler

  setup_all do
    # always create and setup a host
    {:ok, %{host_add: [], host_setup: []}}
  end

  setup [:host_add, :host_setup, :device_add, :devalias_add, :command_add, :dispatch_add]

  describe "Sally.Mutable.Handler.db_actions/1 processes a" do
    @tag device_add: [auto: :mcp23008], devalias_add: []
    @tag dispatch_add: [subsystem: "mut", category: "status"]
    test "well-formed Sally.Dispatch with one DevAlias", ctx do
      dispatch = Should.Be.Struct.named(ctx[:dispatch], Dispatch)

      db_rc = Handler.db_actions(dispatch)
      db_results = Should.Be.Tuple.with_rc(db_rc, :ok)

      Should.Be.map(db_results)

      want_keys = [:aliases, :aligned_0, :device, :seen_list]
      verified_map = Should.Be.Map.with_keys(db_results, want_keys)

      Should.Be.schema(verified_map.device, Device)
      Should.Be.NonEmpty.map(verified_map.aligned_0)

      Should.Be.List.of_schemas(verified_map.aliases, DevAlias)
      Should.Be.List.of_schemas(verified_map.seen_list, DevAlias)
    end

    @tag device_add: [auto: :mcp23008], devalias_add: [count: 5]
    @tag dispatch_add: [subsystem: "mut", category: "status"]
    test "well-formed Sally.Dispatch with multiple DevAlias", ctx do
      dispatch = Should.Be.Struct.named(ctx[:dispatch], Dispatch)

      db_rc = Handler.db_actions(dispatch)
      db_results = Should.Be.Tuple.with_rc(db_rc, :ok)

      Should.Be.map(db_results)

      want_keys = [:aliases, :device, :seen_list]
      verified_map = Should.Be.Map.with_keys(db_results, want_keys)

      Should.Be.schema(verified_map.device, Device)

      for pio <- 0..4 do
        aligned_key = String.to_atom("aligned_#{pio}")
        aligned = Should.Be.Map.with_key(db_results, aligned_key)
        Should.Be.schema(aligned, Command)
      end

      Should.Be.List.of_schemas(verified_map.aliases, DevAlias)
      Should.Be.List.of_schemas(verified_map.seen_list, DevAlias)
    end
  end

  describe "Sally.Mutable.Handler.db_cmd_ack/2 processes a" do
    @tag device_add: [auto: :mcp23008], devalias_add: []
    @tag command_add: [cmd: "on"]
    @tag dispatch_add: [subsystem: "mut", category: "cmdack"]
    test "well formed Sally.Dispatch", ctx do
      dispatch = Should.Be.Struct.named(ctx[:dispatch], Dispatch)

      %Command{id: command_id} = ctx.command
      %DevAlias{id: dev_alias_id} = ctx.dev_alias

      db_rc = Handler.db_cmd_ack(dispatch, command_id, dev_alias_id)
      db_results = Should.Be.Tuple.with_rc(db_rc, :ok)

      map = Should.Be.Map.with_keys(db_results, [:command, :device, :seen_list])
      Should.Be.schema(map.command, Command)
      Should.Be.schema(map.device, Device)
      Should.Be.List.of_schemas(map.seen_list, DevAlias)
    end
  end

  describe "Sally.Mutable.Handler.process/1" do
    @tag device_add: [auto: :mcp23008], devalias_add: []
    @tag command_add: [cmd: "on", track: true]
    @tag dispatch_add: [subsystem: "mut", category: "cmdack"]
    test "handles a cmdack Dispatch", ctx do
      ctx
      |> Should.Be.Map.with_key(:dispatch)
      |> Handler.process()
      |> DispatchAid.assert_processed()
    end

    @tag device_add: [auto: :mcp23008], devalias_add: []
    @tag command_add: []
    @tag dispatch_add: [subsystem: "mut", category: "status"]
    test "handles a status Dispatch", ctx do
      ctx
      |> Should.Be.Map.with_key(:dispatch)
      |> Handler.process()
      |> DispatchAid.assert_processed()
    end
  end
end
