defmodule HelenSwitchTest do
  @moduledoc false
  use ExUnit.Case, async: true

  use HelenTestShould

  # alias Switch.DB.{Alias, Device}
  #
  # @moduletag :switch
  #
  # @states_count 12
  # @states_default for pio <- 0..(@states_count - 1), do: %{state: false, pio: pio}
  #
  # setup_all do
  #   import SwitchTestHelper,
  #     only: [device_default: 1, make_device: 1]
  #
  #   ctx = make_device(%{device: device_default([]), states: @states_default})
  #
  #   fail = pretty("create default device failed", ctx)
  #   assert is_struct(ctx[:device_actual]), fail
  #
  #   # on_exit(fn -> delete_all_dsevices() end)
  #   on_exit(fn -> Switch.cmd_counts_reset([:orphaned, :errors]) end)
  #
  #   {:ok, ctx}
  # end
  #
  # def setup_ctx(ctx) do
  #   import SwitchTestHelper, only: [execute_cmd: 1, freshen: 1, make_alias: 1, make_device: 1]
  #
  #   txn_result =
  #     Repo.transaction(
  #       fn ->
  #         # NOTE: the order of these checks and actions is essential to the test cases
  #         #       for example:  we make a device, then add an alias to execute a cmd
  #         #       and then ultimately freshen it
  #         ctx = if ctx[:make_device], do: make_device(ctx), else: ctx
  #         ctx = if ctx[:make_alias], do: make_alias(ctx), else: ctx
  #         ctx = if ctx[:execute], do: execute_cmd(ctx), else: ctx
  #         if ctx[:freshen], do: freshen(ctx), else: ctx
  #       end,
  #       []
  #     )
  #
  #   should_be_ok_tuple(txn_result)
  #   {_rc, ctx} = txn_result
  #
  #   case ctx[:name] do
  #     name when is_binary(name) ->
  #       status = Switch.status(name)
  #
  #       fail = pretty("status should be a map", ctx)
  #       assert is_map(status), fail
  #
  #       fail = pretty("status should include the alias name")
  #       assert name == status[:name], fail
  #
  #       Map.merge(ctx, %{name: name, status: status})
  #
  #     _x ->
  #       ctx
  #   end
  # end
  #
  # setup ctx do
  #   ctx = setup_ctx(ctx)
  #
  #   if ctx[:debug], do: pretty_puts("setup ctx:", ctx)
  #
  #   {:ok, ctx}
  # end
  #
  # test "can create a switch", %{device_actual: device_actual, device: device} do
  #   should_be_struct(device_actual, Device)
  #
  #   fail = pretty("newly created device name does not match", device_actual)
  #   %Device{device: dev_name} = device_actual
  #   assert dev_name == device, fail
  # end
  #
  # @tag make_alias: true
  # @tag pio: :any
  # @tag name: "Create Alias Test"
  # test "can create a switch alias", %{name: name} do
  #   x = Switch.alias_find(name)
  #
  #   should_be_struct(x, Alias)
  # end
  #
  # @tag make_alias: true
  # @tag pio: :any
  # @tag name: "Status Test"
  # @tag execute: %{cmd: :on, name: "Status Test", opts: []}
  # @tag ack: true
  # test "can get switch status", %{status: status, execute: %{cmd: cmd}} do
  #   should_be_status_map(status)
  #   should_be_cmd_equal(status, cmd)
  #   should_not_be_ttl_expired(status)
  #   should_not_be_pending(status)
  # end
  #
  # @tag pio: :any
  # @tag make_alias: true
  # @tag name: "Command Count Test"
  # @tag execute: %{cmd: :on, name: "Command Count Test"}
  # @tag ack: true
  # test "can get switch command counts" do
  #   cmds = Switch.cmd_counts()
  #   fail = pretty("cmd count should be > 0", cmds)
  #   assert cmds > 0, fail
  #
  #   tracked = Switch.cmds_tracked()
  #   fail = pretty("cmds tracked should be > 0", tracked)
  #   assert tracked > 0, fail
  # end
  #
  # @tag make_alias: true
  # @tag pio: :any
  # @tag name: "Freshen Test"
  # @tag freshen: true
  # test "can freshen an existing switch", %{status: status, name: name} do
  #   fail = ":name should be in status#{pretty(status)}"
  #   assert name == status[:name], fail
  #
  #   fail = "should not be ttl expired"
  #   refute is_map_key(status, :ttl_expired), fail
  # end
  #
  # @tag make_alias: true
  # @tag pio: :any
  # @tag name: "Execute With Ack"
  # @tag execute: %{cmd: :on, name: "Execute With Ack"}
  # # when :cmd_opts are included in the ctx they override opts in the :cmd map
  # @tag cmd_opts: []
  # @tag ack: true
  # test "can switch execute a cmd map and ack",
  #      %{
  #        name: name,
  #        execute_rc: execute_rc
  #      } = ctx do
  #   should_be_ok_tuple(execute_rc)
  #   {_rc, results} = execute_rc
  #
  #   should_be_non_empty_list(ctx, :results)
  #   should_contain_key(results, :refid)
  #
  #   refid = results[:refid]
  #   fail = pretty("refid should be acked", execute_rc)
  #   assert Switch.acked?(refid), fail
  #
  #   status = Switch.status(name)
  #
  #   should_be_non_empty_map(status)
  #
  #   should_be_non_empty_map(status)
  #   should_contain_value(status, cmd: :on)
  # end
  #
  # @tag make_alias: true
  # @tag pio: :any
  # @tag name: "On Test Typical"
  # test "can turn a switch on", %{name: name} do
  #   res = Switch.on(name)
  #
  #   should_be_tuple_with_rc(res, :pending)
  #   {_rc, results} = res
  #
  #   should_be_non_empty_list(results)
  #   should_contain(results, name: name)
  #   should_contain(results, cmd: :on)
  #   should_contain_key(results, :refid)
  #   should_contain_key(results, :refid)
  #   should_contain_key(results, :pub_rc)
  #
  #   pub_rc = results[:pub_rc]
  #   should_be_ok_tuple(pub_rc)
  # end
  #
  # @tag make_alias: true
  # @tag pio: :any
  # @tag name: "Status Test TTL Expired"
  # @tag ttl_ms: 1000
  # test "can get switch status with expired ttl", %{name: name} do
  #   wait_for_ttl = fn ->
  #     for _i <- 1..10, reduce: false do
  #       false ->
  #         case Switch.status(name, ttl_ms: 1) do
  #           %{ttl_expired: true} ->
  #             true
  #
  #           _ ->
  #             Process.sleep(100)
  #             false
  #         end
  #
  #       true ->
  #         true
  #     end
  #   end
  #
  #   fail = "should have seen :ttl_expired"
  #   assert wait_for_ttl.(), fail
  # end
  #
  # @tag make_alias: true
  # @tag pio: :any
  # @tag name: "Detect Missing Name In Execute Test"
  # @tag execute: %{cmd: :on, opts: [lazy: true]}
  # @tag ack: true
  # test "can execute detect a missing name", %{execute_rc: execute_rc} do
  #   should_be_tuple_with_rc(execute_rc, :invalid_cmd)
  # end
end
