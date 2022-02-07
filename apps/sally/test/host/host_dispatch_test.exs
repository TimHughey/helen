# defmodule SallyHostDispatchTest do
#   @moduledoc false
#   use ExUnit.Case, async: true
#
#   @moduletag sally: true, sally_host_dispatch: true
#
#   setup [:setup_data, :setup_message]
#
#   @tag category: "boot"
#   @tag host_ident: "host.hostmsgtest"
#   @tag host_name: "host-message-test"
#   @tag mtime: :now
#   @tag payload: %{build_date: "Jul 13 1971", build_time: "13:05:00"}
#   test "can Sally.Dispatch.accept/1 handle a boot message", ctx do
#     assert %Sally.Dispatch{category: "boot", env: "test", data: nil, log: [msg: true],
#              category: "boot"
#            } = ctx.dispatch
#   end
#
#   @tag category: "run"
#   @tag host_ident: "host.hostmsgtest"
#   @tag host_name: "host-message-test"
#   @tag mtime: -100_000
#   @tag payload: %{}
#   test "can Sally.Dispatch.accept/1 handle an old message", ctx do
#     assert %Sally.Dispatch{valid?: false, halt_reason: halt_reason} = ctx.dispatch
#     assert halt_reason =~ ~r/old/
#   end
#
#   @tag category: "ota"
#   @tag host_ident: "host.hostmsgtest"
#   @tag host_name: "host-message-test"
#   @tag mtime: :none
#   @tag payload: %{}
#   test "can Sally.Dispatch.accept/1 handle a message missing the mtime key", ctx do
#     assert %Sally.Dispatch{valid?: false, halt_reason: halt_reason} = ctx.dispatch
#     assert halt_reason =~ ~r/mtime is missing/
#   end
#
#   @tag category: "bad"
#   @tag host_ident: "host.hostmsgtest"
#   @tag host_name: "host-message-test"
#   @tag mtime: :now
#   @tag payload: %{}
#   test "can Sally.Dispatch.accept/1 handle a message with invalid category", ctx do
#     assert %Sally.Dispatch{valid?: false, halt_reason: halt_reason} = ctx.dispatch
#     assert halt_reason =~ ~r/unknown subsystem/
#   end
#
#   defp make_mtime(ctx) do
#     case ctx.mtime do
#       x when is_number(x) -> System.os_time(:millisecond) + x
#       _ -> System.os_time(:millisecond)
#     end
#   end
#
#   defp setup_data(ctx) do
#     base_data = if ctx.mtime == :none, do: %{log: true}, else: %{mtime: make_mtime(ctx), log: true}
#     data = Map.merge(ctx.payload || %{}, base_data)
#
#     %{data: data}
#   end
#
#   defp setup_message(ctx) do
#     dispatch =
#       {["test", ctx.host_ident, "host", ctx.category, []], Msgpax.pack!(ctx.data, iodata: false)}
#       |> Sally.Dispatch.accept()
#
#     %{dispatch: dispatch}
#   end
# end
