defmodule SallyHostHandlerTest do
  @moduledoc false

  use ExUnit.Case
  use Should

  @host_ident_default "sally.hosthand000"
  # @host_name_default "Sally Host Initial"

  @moduletag host_handler: true, sally_host: true

  alias Sally.Host.Handler

  setup_all ctx do
    ctx
  end

  setup [:setup_init]

  @tag setup: false
  test "can Host Handler can process a basic message", _ctx do
    default_msg_in() |> Handler.handle_message()
  end

  @tag msg_category: "ds"
  @tag payload: %{mut: true, pios: 4}
  test "can Host Handler process MsgIn reading", ctx do
    res = ctx.handler

    should_be_non_empty_map(res)

    should_be_schema(res.host, Sally.Host)
    should_be_schema(res.device, Sally.Device)
    should_be_struct(res.msg_in, Sally.MsgIn)
  end

  defp default_msg_in(opts \\ %{}) do
    payload = Map.merge(%{mtime: System.os_time(:millisecond)}, opts[:payload] || %{})

    {[
       "test",
       "r",
       opts[:host_ident] || @host_ident_default,
       opts[:msg_category] || "boot",
       opts[:host_name] || @host_ident_default,
       opts[:adjunct] || []
     ], payload |> Msgpax.pack!() |> IO.iodata_to_binary()}
    |> Sally.MsgIn.create()
  end

  defp setup_init(ctx) do
    put = fn res, x -> put_in(ctx, [x], res) end

    run_setup = if ctx[:setup] |> is_nil(), do: true, else: ctx[:setup]
    if run_setup, do: ctx |> default_msg_in() |> Handler.handle_message() |> put.(:handler), else: ctx
  end
end
