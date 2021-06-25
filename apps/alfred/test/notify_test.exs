# defmodule AlfredNotifyTest do
#   use ExUnit.Case
#   use Should
#
#   alias Alfred.{KnownName, NamesAgent, Notify, NotifyTo}
#   alias NamesTestHelper, as: NamesHelper
#
#   @moduletag :notify
#
#   setup_all ctx do
#     Map.merge(ctx, %{make_names: 10, just_saw: :auto})
#   end
#
#   setup ctx do
#     ctx
#     |> NamesHelper.make_names()
#     |> NamesHelper.make_seen()
#     |> NamesHelper.just_saw()
#     |> NamesHelper.random_name()
#   end
#
#   test "can register a pid via Alfred Notify", ctx do
#     rc = Alfred.notify_register(ctx.random_name, interval: "PT1S", link: false)
#     should_be_ok_tuple(rc)
#
#     {:ok, notify_to} = rc
#     should_be_struct(notify_to, NotifyTo)
#   end
#
#   test "can NotifyServer send notifications when names are seen", ctx do
#     rc = Alfred.notify_register(ctx.random_name, interval: "PT1S", link: false)
#     should_be_ok_tuple(rc)
#
#     {:ok, notify_to} = rc
#     should_be_struct(notify_to, NotifyTo)
#
#     NamesAgent.just_saw(ctx.seen_list)
#     [%KnownName{name: notify_to.name}] |> Notify.notify()
#
#     notify_ref = notify_to.ref
#     random_name = ctx.random_name
#
#     notify_msg =
#       receive do
#         {Alfred, ^notify_ref, {:notify, ^random_name}} = x -> x
#       after
#         1000 -> :timeout
#       end
#
#     refute notify_msg == :timeout
#   end
#
#   test "can NotifyServer detect when a pid registered for notifications exitted", ctx do
#     register = fn ->
#       Alfred.notify_register(ctx.random_name, interval: "PT0.001S", link: false)
#     end
#
#     spawned_pid = Process.spawn(register, [])
#
#     # wait for the spawned pid to exit
#     for _x <- 1..10, reduce: Process.alive?(spawned_pid) do
#       true ->
#         Process.sleep(10)
#         Process.alive?(spawned_pid)
#
#       false ->
#         false
#     end
#
#     # simulate the inbound msg map
#     %{states_rc: {:ok, ctx.seen_list}} |> Alfred.just_saw()
#     [%KnownName{name: ctx.random_name}] |> Notify.notify()
#
#     # implict test via logging
#     Process.sleep(100)
#   end
#
#   test "can NotifyServer return a list of all names registered for notification", ctx do
#     # bonus test of handling linked processes
#     Alfred.notify_register(ctx.random_name, interval: "PT1S")
#
#     registered = Notify.names_registered()
#     should_be_non_empty_list(registered)
#   end
#
#   test "can Notify detect unknown name when registering for notifications", _ctx do
#     res = Alfred.notify_register("foobar", notify_interval: "PT1S")
#     should_be_tuple(res)
#     {rc, msg} = res
#
#     fail = pretty("rc should be {:failed, 'unknown name: foobar'", rc)
#     assert rc == :failed, fail
#     assert msg =~ "unknown name", fail
#   end
#
#   test "can Notify detect invalid interval when registering for notifications", ctx do
#     res = Alfred.notify_register(ctx.random_name, interval: "PT100G")
#     should_be_tuple(res)
#
#     {rc, msg} = res
#
#     fail = pretty("rc should be {:failed, 'invalid interval: ...'", rc)
#     assert rc == :failed, fail
#     assert msg =~ "invalid interval", fail
#   end
# end
