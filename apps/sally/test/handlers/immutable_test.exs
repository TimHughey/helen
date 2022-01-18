defmodule Sally.ImmutableHandlerTest do
  use ExUnit.Case, async: true
  use Sally.TestAid
  require Sally.DispatchAid

  @moduletag sally: true, sally_immutable_handler: true

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
      assert %{dispatch: %Sally.Dispatch{} = dispatch} = ctx

      assert {:ok,
              %{
                aliases: [%Sally.DevAlias{} | _],
                datapoint: [%Sally.Datapoint{} | _],
                device: %Sally.Device{}
              }} = Sally.Immutable.Handler.db_actions(dispatch)
    end
  end

  describe "Sally.Immutable.Handler.process/1" do
    @tag device_add: [auto: :ds], devalias_add: []
    @tag dispatch_add: [subsystem: "immut", category: "celsius", data: %{temp_c: 21.5}]
    test "handles a celsius Dispatch", ctx do
      assert %{dispatch: %Sally.Dispatch{} = dispatch} = ctx

      dispatch
      |> Sally.Immutable.Handler.process()
      |> Sally.DispatchAid.assert_processed()
    end

    @tag device_add: [auto: :ds], devalias_add: []
    @tag dispatch_add: [subsystem: "immut", category: "celsius", status: "error", data: %{temp_c: 21.5}]
    test "handles an error Dispatch", ctx do
      assert %{dispatch: %Sally.Dispatch{} = dispatch} = ctx

      assert %Sally.Dispatch{} = Sally.Immutable.Handler.process(dispatch)
    end
  end

  describe "Sally.Immutable.Handler.post_process/1" do
    @tag device_add: [auto: :ds], devalias_add: []
    @tag dispatch_add: [subsystem: "immut", category: "relhum", data: %{temp_c: 21.5, relhum: 54.3}]
    test "handles a valid Dispatch with datapoints", ctx do
      assert %{dispatch: %Sally.Dispatch{} = dispatch} = ctx

      dispatch
      |> Sally.Immutable.Handler.process()
      |> Sally.DispatchAid.assert_processed()
      |> Sally.Immutable.Handler.post_process()
      |> Sally.DispatchAid.assert_processed()
    end
  end
end
