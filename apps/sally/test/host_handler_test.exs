defmodule SallyHostHandlerTest do
  @moduledoc false

  use ExUnit.Case
  use Should

  @moduletag host_handler: true, sally_host: true

  alias Sally.Host

  setup [:setup_filter, :setup_payload_and_packed]

  @tag setup: true
  @tag category: "boot"
  @tag host_ident: "sally.hostprocessor000"
  @tag host_name: "sally.hostprocessor000"
  test "can Host Handler can process a boot message", ctx do
    # simulare the steps taken by Sally.Mqtt.Handler.handle_message/3 and Host.Handler.process/1
    x = {ctx.filter, ctx.packed} |> Host.Message.accept() |> Host.Handler.process()

    # initially set tested to keys we don't need to test
    tested = [:env, :log]
    fail = pretty("finalized Message did not match", x)
    assert x.valid? == true, fail
    tested = [:valid?] ++ tested
    assert x.category == "boot", fail
    tested = [:category] ++ tested
    assert map_size(x.data) == 0, fail
    tested = [:data] ++ tested
    assert DateTime.compare(x.final_at, x.sent_at) == :gt, fail
    tested = [:final_at, :sent_at] ++ tested
    should_be_schema(x.host, Host)
    tested = [:host] ++ tested
    assert x.ident == ctx.host_ident, fail
    tested = [:ident] ++ tested
    refute x.invalid_reason, fail
    tested = [:invalid_reason] ++ tested
    assert x.name == ctx.host_name, fail
    tested = [:name] ++ tested
    assert x.payload == :unpacked, fail
    tested = [:payload] ++ tested
    assert DateTime.compare(x.recv_at, x.sent_at) == :gt, fail
    tested = [:recv_at] ++ tested
    should_be_struct(x.reply, Host.Reply)
    tested = [:reply] ++ tested
    assert x.routed == :no, fail
    tested = [:routed] ++ tested

    # confirm all keys were tested
    untested = x |> Map.from_struct() |> Map.drop(tested)
    failed = pretty("untested keys", untested)
    assert map_size(untested) == 0, failed
  end

  # NOTE: the filter created is the reduced filter created by Mqtt.Handler.handle_message/3
  # and is intended for consumption by Host.Message.accept/1
  defp setup_filter(ctx) do
    put = fn x -> put_in(ctx, [:filter], x) end
    ["test", ctx[:category], ctx[:host_ident], ctx[:host_name]] |> put.()
  end

  # NOTE! must use iodata: false since this packed data won't be sent. rather, we're simulating the
  # receipt of the packed data
  defp setup_payload_and_packed(ctx) do
    payload = Map.merge(%{mtime: System.os_time(:millisecond)}, ctx[:payload] || %{})

    packed = Msgpax.pack!(payload, iodata: false)

    put_in(ctx, [:payload], payload) |> put_in([:packed], packed)
  end
end
