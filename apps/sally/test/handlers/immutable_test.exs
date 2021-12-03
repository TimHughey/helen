defmodule Sally.ImmutableHandlerTest do
  use ExUnit.Case, async: true
  use Should
  use Sally.TestAid

  @moduletag sally: true, sally_immutable_handler: true

  alias Sally.{Datapoint, DevAlias, Device}
  alias Sally.Dispatch
  alias Sally.Immutable.Handler

  setup_all do
    # always create and setup a host
    {:ok, %{host_add: [], host_setup: []}}
  end

  setup [:host_add, :host_setup, :device_add, :devalias_add, :dispatch_add]

  @setup_base device_add: [], devalias_add: []

  describe "Sally.ImmutableHandler.db_actions/1" do
    @tag @setup_base
    @tag dispatch_add: [subsystem: "immut", category: "celsius", data: %{temp_c: 21.2}]
    test "processes a well-formed Sally.Dispatch", ctx do
      dispatch = Should.Be.Struct.named(ctx[:dispatch], Dispatch)

      db_rc = Handler.db_actions(dispatch)
      db_results = Should.Be.Tuple.with_rc(db_rc, :ok)

      Should.Be.Map.check(db_results)
      want_keys = [:aliases, :datapoint, :device, :seen_list]
      verified_map = Should.Be.Map.with_keys(db_results, want_keys)

      Should.Be.List.of_schemas(verified_map.aliases, DevAlias)
      Should.Be.List.of_schemas(verified_map.datapoint, Datapoint)
      Should.Be.schema(verified_map.device, Device)
      Should.Be.List.of_schemas(verified_map.seen_list, DevAlias)
    end
  end

  describe "Sally.Immutable.Handler.process/1" do
    @tag device_add: [auto: :ds], devalias_add: []
    @tag dispatch_add: [subsystem: "immut", category: "celsius", data: %{temp_c: 21.5}]
    test "handles a celsius Dispatch", ctx do
      ctx
      |> Should.Be.Map.with_key(:dispatch)
      |> Handler.process()
      |> DispatchAid.assert_processed()
    end

    @tag device_add: [auto: :ds], devalias_add: []
    @tag dispatch_add: [subsystem: "immut", category: "celsius", status: "error", data: %{temp_c: 21.5}]
    test "handles an error Dispatch", ctx do
      ctx
      |> Should.Be.Map.with_key(:dispatch)
      |> Handler.process()
      |> Should.Be.struct(Dispatch)
    end
  end

  describe "Sally.Immutable.Handler.post_process/1" do
    @tag device_add: [auto: :ds], devalias_add: []
    @tag dispatch_add: [subsystem: "immut", category: "relhum", data: %{temp_c: 21.5, relhum: 54.3}]
    test "handles a valid Dispatch with datapoints", ctx do
      ctx
      |> Should.Be.Map.with_key(:dispatch)
      |> Handler.process()
      |> DispatchAid.assert_processed()
      |> Handler.post_process()
      |> DispatchAid.assert_processed()
    end
  end
end
