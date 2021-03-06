defmodule SallyHostMsgTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use Should

  alias Sally.Dispatch, as: Msg

  @moduletag :host_message

  setup [:setup_data, :setup_message]

  @tag category: "boot"
  @tag host_ident: "host.hostmsgtest"
  @tag host_name: "host-message-test"
  @tag mtime: :now
  @tag payload: %{build_date: "Jul 13 1971", build_time: "13:05:00"}
  test "can Sally.Dispatch.accept/1 handle a boot message", ctx do
    x = ctx.accepted_message

    fail = pretty("Msg did not match", x)
    assert x.valid? == true, fail
    assert is_map(x.data), fail
    refute x.data[:mtime] < ctx.data.mtime, fail
    assert x.log == [msg: true], fail
  end

  @tag category: "run"
  @tag host_ident: "host.hostmsgtest"
  @tag host_name: "host-message-test"
  @tag mtime: -100_000
  @tag payload: %{}
  test "can Sally.Dispatch.accept/1 handle an old message", ctx do
    x = ctx.accepted_message

    fail = pretty("Msg did not match", x)
    refute x.valid?, fail
    assert x.invalid_reason =~ "old"
  end

  @tag category: "ota"
  @tag host_ident: "host.hostmsgtest"
  @tag host_name: "host-message-test"
  @tag mtime: :none
  @tag payload: %{}
  test "can Sally.Dispatch.accept/1 handle a message missing the mtime key", ctx do
    x = ctx.accepted_message

    fail = pretty("Msg did not match", x)
    refute x.valid?, fail
    assert x.invalid_reason == "mtime is missing"
  end

  @tag category: "bad"
  @tag host_ident: "host.hostmsgtest"
  @tag host_name: "host-message-test"
  @tag mtime: :now
  @tag payload: %{}
  test "can Sally.Dispatch.accept/1 handle a message with invalid category", ctx do
    x = ctx.accepted_message

    fail = pretty("Msg did not match", x)
    refute x.valid?, fail
    assert x.invalid_reason =~ "unknown subsystem/category"
  end

  defp accept(ctx) do
    {["test", ctx.host_ident, "host", ctx.category, []], Msgpax.pack!(ctx.data, iodata: false)}
    |> Msg.accept()
  end

  defp make_mtime(ctx) do
    case ctx.mtime do
      x when is_number(x) -> System.os_time(:millisecond) + x
      _ -> System.os_time(:millisecond)
    end
  end

  defp setup_data(ctx) do
    base_data = if ctx.mtime == :none, do: %{log: true}, else: %{mtime: make_mtime(ctx), log: true}
    data = Map.merge(ctx.payload || %{}, base_data)

    put_in(ctx, [:data], data)
  end

  defp setup_message(ctx) do
    put_in(ctx, [:accepted_message], accept(ctx))
  end
end
