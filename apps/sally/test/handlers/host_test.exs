defmodule SallyHostHandlerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  @moduletag sally: true, sally_host_handler: true

  setup [:setup_filter, :setup_payload_and_packed]

  @tag setup: true
  @tag category: "boot"
  @tag host_ident: "sally.hostprocessor000"
  @tag host_name: "sally.hostprocessor000"
  test "can Host Handler can process a boot message", ctx do
    # simulare the steps taken by Sally.Mqtt.Handler.handle_message/3 and Host.Handler.process/1
    dispatch = Sally.Dispatch.accept({ctx.filter, ctx.packed}) |> Sally.Host.Handler.process()
    host_ident = ctx.host_ident

    assert %Sally.Dispatch{
             valid?: true,
             category: "boot",
             data: %{},
             host: :not_loaded,
             invalid_reason: "none",
             sent_at: %DateTime{} = sent_at,
             payload: :unpacked,
             recv_at: %DateTime{} = recv_at,
             txn_info: {:ok, %{host: %Sally.Host{ident: ^host_ident}}},
             routed: :no
           } = dispatch

    assert DateTime.compare(recv_at, sent_at) == :gt
  end

  # NOTE: the filter created is the reduced filter created by Mqtt.Handler.handle_message/3
  # and is intended for consumption by Sally.Dispatch.accept/1
  defp setup_filter(%{category: "boot"} = ctx) do
    %{filter: ["test", ctx[:host_ident], "host", ctx.category, []]}
  end

  defp setup_filter(%{category: _}), do: %{filter: ["test"]}

  # NOTE! must use iodata: false since this packed data won't be sent. rather, we're simulating the
  # receipt of the packed data
  defp setup_payload_and_packed(ctx) do
    payload = Map.merge(%{mtime: System.os_time(:millisecond)}, ctx[:payload] || %{})

    packed = Msgpax.pack!(payload, iodata: false)

    %{payload: payload, packed: packed}
  end
end
