defmodule Sally.HostDispatchTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_host_handler: true

  setup [:dispatch_add]

  describe "Sally.Host.Dispatch processes" do
    @tag dispatch_add: [subsystem: "host", category: "startup", host: []]
    test "a host startup message for a previously seen host", ctx do
      assert %{dispatch: %Sally.Dispatch{payload: payload} = dispatch} = ctx
      assert [_ | _] = filter = Sally.DispatchAid.make_filter(dispatch)

      # NOTE: Sally.DispatchAid.add/2 adds echo option
      assert {:ok, %{}} = Sally.Mqtt.Handler.handle_message(filter, payload, %{})

      assert_receive(
        %Sally.Dispatch{
          data: %{},
          filter_extra: [],
          final_at: %DateTime{},
          # NOTE: duplicate variable names in a pattern match must be equal
          host: %Sally.Host{ident: host_ident},
          ident: host_ident,
          invalid_reason: :none,
          payload: :unpacked,
          recv_at: %DateTime{},
          routed: :ok,
          sent_at: %DateTime{},
          txn_info: %{},
          valid?: true
        },
        500
      )
    end

    @tag dispatch_add: [subsystem: "host", category: "run", host: []]
    test "a host run message for a previously seen host", ctx do
      assert %{dispatch: %Sally.Dispatch{payload: payload} = dispatch} = ctx
      assert [_ | _] = filter = Sally.DispatchAid.make_filter(dispatch)

      # NOTE: Sally.DispatchAid.add/2 adds echo option
      assert {:ok, %{}} = Sally.Mqtt.Handler.handle_message(filter, payload, %{})

      assert_receive(
        %Sally.Dispatch{
          data: %{},
          filter_extra: [],
          final_at: %DateTime{},
          # NOTE: duplicate variable names in a pattern match must be equal
          host: %Sally.Host{ident: host_ident},
          ident: host_ident,
          invalid_reason: :none,
          payload: :unpacked,
          recv_at: %DateTime{},
          routed: :ok,
          sent_at: %DateTime{},
          txn_info: %{},
          valid?: true
        },
        500
      )
    end

    @tag dispatch_add: [subsystem: "host", category: "boot", host: [:ident_only]]
    test "a host boot message for a previously unseen host", ctx do
      assert %{dispatch: %Sally.Dispatch{payload: payload} = dispatch} = ctx
      assert [_ | _] = filter = Sally.DispatchAid.make_filter(dispatch)

      assert {:ok, %{}} = Sally.Mqtt.Handler.handle_message(filter, payload, %{})

      assert_receive(
        %Sally.Dispatch{
          data: %{},
          filter_extra: ["generic"],
          final_at: %DateTime{},
          host: %Sally.Host{ident: host_ident},
          ident: host_ident,
          invalid_reason: :none,
          payload: :unpacked,
          recv_at: %DateTime{},
          routed: :ok,
          sent_at: %DateTime{},
          txn_info: %{},
          valid?: true
        },
        500
      )
    end
  end
end
