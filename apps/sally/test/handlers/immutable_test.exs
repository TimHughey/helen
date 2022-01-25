defmodule Sally.ImmutableHandlerTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_immutable_handler: true

  setup [:dispatch_add]

  describe "Sally.Immutable.Handler processes" do
    @tag dev_alias_opts: [auto: :ds, daps: [history: 1, echo: :dispatch]]
    @tag dispatch_add: [subsystem: "immut", category: "celsius"]
    test "a status message (celsius)", ctx do
      assert %{dispatch: dispatch, dispatch_filter: filter} = ctx
      assert %Sally.Dispatch{txn_info: %{} = create_info} = dispatch
      assert %{dev_alias: %Sally.DevAlias{name: name}} = create_info
      assert %{dap_history: [_ | _]} = create_info

      status_before = Alfred.status(name, [])
      assert %Alfred.Status{detail: before_detail, rc: :ok} = status_before

      assert %{payload: payload, filter_extra: filter_extra} = dispatch
      assert [device_ident, "ok"] = filter_extra
      device = Sally.Device.find(device_ident)
      assert %Sally.Device{ident: ^device_ident} = device

      assert {:ok, %{}} = Sally.Mqtt.Handler.handle_message(filter, payload, %{})

      assert_receive(%Sally.Dispatch{} = dispatch, 200)

      assert %{invalid_reason: :none, subsystem: "immut", valid?: true} = dispatch
      assert %{filter_extra: [^device_ident, "ok"]} = dispatch
      assert %{txn_info: %{} = txn_info} = dispatch

      # NOTE: txn_info validations
      assert %{aliases: [%Sally.DevAlias{}]} = txn_info
      assert %{datapoint: [%Sally.Datapoint{}]} = txn_info
      assert %{device: %Sally.Device{}} = txn_info
      assert %{just_saw_db: {1, [%Sally.DevAlias{}]}} = txn_info
      assert %{_post_process_: post_process} = txn_info
      assert [{<<_::binary>> = _dev_alias_name, :ok}] = post_process

      status_after = Alfred.status(name, [])
      assert %Alfred.Status{detail: after_detail, rc: :ok} = status_after

      # NOTE: ensure the status detail has changed
      refute before_detail == after_detail
    end
  end
end
