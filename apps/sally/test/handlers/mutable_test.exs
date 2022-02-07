defmodule Sally.MutableDispatchTest do
  use ExUnit.Case, async: true
  use Sally.TestAid
  require Sally.DispatchAid

  @moduletag sally: true, sally_mutable_handler: true

  setup [:dispatch_add]

  describe "Sally.Mutable.Dispatch processes" do
    @tag dev_alias_opts: [auto: :mcp23008, count: 5, cmds: [history: 5, latest: :busy, echo: :dispatch]]
    @tag dispatch_add: [subsystem: "mut", category: "cmdack"]
    test "a cmdack message", ctx do
      assert %{dispatch: %Sally.Dispatch{} = dispatch} = ctx
      assert %{payload: payload, filter_extra: [<<_::binary>> = refid]} = dispatch
      assert [_ | _] = filter = Sally.DispatchAid.make_filter(dispatch)

      # NOTE: validate the command is tracked
      tracked_cmd = Sally.Command.tracked_info(refid)

      assert %Sally.Command{id: cmd_id, cmd: cmd, refid: ^refid} = tracked_cmd

      dev_alias = Sally.DevAlias.find(tracked_cmd.dev_alias_id)
      assert %{name: name} = dev_alias

      assert {:ok, %{}} = Sally.Mqtt.Handler.handle_message(filter, payload, %{})

      assert_receive(%Sally.Dispatch{} = dispatch, 500)

      assert %{halt_reason: :none, subsystem: "mut", valid?: true} = dispatch
      assert %{filter_extra: [^refid]} = dispatch
      assert %{txn_info: %{aliases: %Sally.DevAlias{name: ^name}}} = dispatch

      status = Alfred.status(name, [])
      assert %Alfred.Status{rc: :ok, name: ^name} = status

      raw = Alfred.Status.raw(status)
      assert %{name: ^name, status: %{id: ^cmd_id, cmd: ^cmd, refid: ^refid}} = raw
    end

    @tag capture_log: true
    @tag dev_alias_opts: [auto: :pwm, count: 2, cmds: [history: 3, echo: :dispatch]]
    @tag dispatch_add: [subsystem: "mut", category: "status"]
    test "a status message", ctx do
      assert %{dispatch: %Sally.Dispatch{} = dispatch} = ctx
      assert %{payload: payload} = dispatch
      assert [_ | _] = filter = Sally.DispatchAid.make_filter(dispatch)

      assert {:ok, %{}} = Sally.Mqtt.Handler.handle_message(filter, payload, %{})

      assert_receive(%Sally.Dispatch{} = dispatch, 150)

      assert %{halt_reason: :none, subsystem: "mut", valid?: true} = dispatch
      assert %{filter_extra: [_device_ident, "ok"]} = dispatch
      assert %{txn_info: %{} = txn_info} = dispatch

      aligned = Enum.filter(txn_info, fn {key, _v} -> match?({:aligned, _}, key) end)
      :ok = Enum.each(aligned, fn kv -> assert {{:aligned, <<_::binary>>}, %{}} = kv end)

      assert Enum.count(aligned) == 2
    end
  end
end
