defmodule SallyHostHandlerTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use Should

  @moduletag sally: true, sally_host_handler: true

  alias Sally.Host

  setup [:setup_filter, :setup_payload_and_packed]

  @tag setup: true
  @tag category: "boot"
  @tag host_ident: "sally.hostprocessor000"
  @tag host_name: "sally.hostprocessor000"
  test "can Host Handler can process a boot message", ctx do
    # simulare the steps taken by Sally.Mqtt.Handler.handle_message/3 and Host.Handler.process/1
    x = {ctx.filter, ctx.packed} |> Sally.Dispatch.accept() |> Host.Handler.process()

    # initially set tested to keys we don't need to test
    tested = [:env, :subsystem, :filter_extra, :log, :results, :final_at, :seen_list]
    fail = pretty("finalized Message did not match", x)
    assert x.valid? == true, fail
    tested = [:valid?] ++ tested
    assert x.category == "boot", fail
    tested = [:category] ++ tested
    assert map_size(x.data) == 0, fail
    tested = [:data] ++ tested
    Should.Be.schema(x.host, Host)
    tested = [:host] ++ tested
    assert x.ident == ctx.host_ident, fail
    tested = [:ident] ++ tested
    assert x.invalid_reason == "none", fail
    tested = [:invalid_reason] ++ tested
    Should.Be.struct(x.sent_at, DateTime)
    tested = [:sent_at] ++ tested
    assert x.payload == :unpacked, fail
    tested = [:payload] ++ tested
    assert DateTime.compare(x.recv_at, x.sent_at) == :gt, fail
    tested = [:recv_at] ++ tested
    assert x.routed == :no, fail
    tested = [:routed] ++ tested

    # confirm all keys were tested
    untested = x |> Map.from_struct() |> Map.drop(tested)
    failed = pretty("untested keys", untested)
    assert map_size(untested) == 0, failed
  end

  # NOTE: the filter created is the reduced filter created by Mqtt.Handler.handle_message/3
  # and is intended for consumption by Sally.Dispatch.accept/1
  defp setup_filter(ctx) do
    put = fn x -> put_in(ctx, [:filter], x) end

    case ctx.category do
      "boot" -> ["test", ctx[:host_ident], "host", ctx.category, []] |> put.()
      _ -> ["test"] |> put.()
    end
  end

  # NOTE! must use iodata: false since this packed data won't be sent. rather, we're simulating the
  # receipt of the packed data
  defp setup_payload_and_packed(ctx) do
    payload = Map.merge(%{mtime: System.os_time(:millisecond)}, ctx[:payload] || %{})

    packed = Msgpax.pack!(payload, iodata: false)

    %{payload: payload, packed: packed}

    #  put_in(ctx, [:payload], payload) |> put_in([:packed], packed)
  end
end
