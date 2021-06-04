defmodule SallyPwmMsgHandlerTest do
  @moduledoc false

  ##
  ## Test of basic Device and Alias creation via TestSupport
  ##

  use ExUnit.Case
  use Should

  @device_ident_default "msg-handler-default"
  @device_host_default "sally.test-msg-handler-default"
  @defaults [
    device_opts: [host: @device_host_default, ident: @device_ident_default, pios: 4],
    category: "pwm"
  ]

  @moduletag pwm_msg_handler: true, defaults: @defaults

  alias Alfred.ExecCmd
  alias Sally.{MsgIn, MsgInFlight}
  alias Sally.PulseWidth.DB
  alias Sally.PulseWidth.{Execute, MsgHandler}

  setup_all ctx do
    ctx
  end

  setup [
    :setup_base_data,
    :setup_additional_data,
    :setup_msg_in,
    :setup_handle_msg,
    :setup_create_dev_alias,
    :setup_execute,
    :setup_dump_ctx
  ]

  # @tag dump_ctx: [:msg_in, :inflight]
  test "can PulseWidth.MsgHandler.handle_message/1 process the ident", ctx do
    validate_ident(ctx)
  end

  # @tag dump_ctx: true
  @tag create_dev_alias: [name: "Handle Cmd Ack", pio: 0]
  @tag exec_cmd: %ExecCmd{cmd: "on"}
  test "can PulseWidth.MsgHandler.handle_message/1 process cmd ack", ctx do
    validate_ident(ctx)

    cmdack_data = %{
      pios: ctx.inflight.ident.pios,
      refid: ctx.execute.refid,
      mtime: System.os_time(:millisecond)
    }

    %{msg_in: cmdack_msg_in} = %{ctx | data: cmdack_data} |> put_in([:cmdack], true) |> setup_msg_in()

    inflight = MsgHandler.handle_message(cmdack_msg_in)
    should_be_struct(inflight, MsgInFlight)
    should_be_schema(inflight.ident, DB.Device)
    should_be_non_empty_list(inflight.just_saw)
    should_be_ok_tuple(inflight.metric_rc)
    should_be_struct(inflight.release, Broom.TrackerEntry)

    receive do
      _broom_release -> nil
    after
      10_000 -> nil
    end
  end

  # @tag skip: true
  # @tag dump_ctx: true
  test "can PulseWidth.MsgHandler.handle_message/1 report message", ctx do
    validate_ident(ctx)
    device = ctx.inflight.ident

    _dev_aliases = for x <- 0..3, do: DB.Alias.create(device, name: "Report #{x}", pio: x)

    pios = @defaults[:device_opts][:pios]
    read_micros = :rand.uniform(10) + 19

    report_data = %{
      :mtime => System.os_time(:millisecond),
      0 => "on",
      1 => "off",
      2 => "custom1",
      3 => "custom2",
      pios: pios,
      read_us: read_micros
    }

    %{msg_in: report_msg_in} = %{ctx | data: report_data} |> setup_msg_in()

    inflight = MsgHandler.handle_message(report_msg_in)
    should_be_struct(inflight, MsgInFlight)
    should_be_schema(inflight.ident, DB.Device)
    should_be_non_empty_list(inflight.applied_data)
    should_be_schema(inflight.applied_data |> hd(), DB.Alias)
    should_be_non_empty_list(inflight.just_saw)
    should_be_non_empty_list(inflight.metrics)
    should_be_empty_list(inflight.faults)

    inspect(inflight.just_saw, pretty: true) |> IO.puts()
  end

  defp setup_additional_data(ctx) do
    put_in_ctx = fn x -> put_in(ctx, [:data], x) end

    Map.merge(ctx.data, ctx[:additional_data] || %{}) |> put_in_ctx.()
  end

  defp setup_base_data(ctx) do
    put_in_ctx = fn x -> put_in(ctx, [:data], x) end

    pios = ctx[:pios] || @defaults[:device_opts][:pios]
    mtime = System.os_time(:millisecond)

    %{mtime: mtime, pios: pios} |> put_in_ctx.()
  end

  defp setup_create_dev_alias(ctx) do
    put_in_ctx = fn {:ok, x} -> put_in(ctx, [:dev_alias], x) end

    case ctx[:create_dev_alias] do
      x when is_list(x) -> DB.Alias.create(ctx.inflight.ident, x) |> put_in_ctx.()
      _ -> ctx
    end
  end

  defp setup_dump_ctx(ctx) do
    case ctx do
      %{dump_ctx: x} when is_list(x) -> ["\n", Map.take(ctx, x) |> inspect(pretty: true), "\n"] |> IO.puts()
      %{dump_ctx: true} -> ["\n", ctx |> inspect(pretty: true), "\n"] |> IO.puts()
      _ -> nil
    end

    ctx
  end

  defp setup_execute(ctx) do
    put_in_ctx = fn x -> put_in(ctx, [:execute], x) end

    make_cmd = fn ec ->
      cmd_opts = [notify_when_released: true, force: true] ++ ec.cmd_opts
      %ExecCmd{ec | name: ctx.dev_alias.name, cmd_opts: cmd_opts}
    end

    case ctx[:exec_cmd] do
      x when is_nil(x) -> ctx
      %ExecCmd{} = ec -> ec |> make_cmd.() |> Execute.cmd() |> put_in_ctx.()
    end
  end

  defp setup_handle_msg(ctx) do
    put_in_ctx = fn x -> put_in(ctx, [:inflight], x) end

    case ctx[:handle_msg] do
      x when is_nil(x) or x == true -> ctx.msg_in |> MsgHandler.handle_message() |> put_in_ctx.()
      _ -> ctx
    end
  end

  defp setup_msg_in(ctx) do
    host = ctx[:host] || @defaults[:device_opts][:host]
    ident = ctx[:ident] || @defaults[:device_opts][:ident]
    cmdack = if ctx[:cmdack], do: "cmdack", else: []

    put_in_ctx = fn x -> put_in(ctx, [:msg_in], x) end

    filters = ["test", "r", host, @defaults[:category], ident, cmdack] |> List.flatten()
    payload = Msgpax.pack!(ctx[:data]) |> IO.iodata_to_binary()

    MsgIn.create(filters, payload)
    |> put_in_ctx.()
  end

  defp validate_ident(ctx) do
    should_be_struct(ctx.inflight, MsgInFlight)
    should_be_schema(ctx.inflight.ident, DB.Device)

    msg_in = ctx.msg_in
    x = ctx.inflight.ident

    fail = pretty("Ident result did not match", x)
    assert x.host == msg_in.host, fail
    assert x.ident == msg_in.ident, fail
    assert x.pios == msg_in.data.pios, fail
    refute Ecto.assoc_loaded?(x.aliases), fail
    assert DateTime.compare(x.inserted_at, x.last_seen_at) != :eq, fail
    assert DateTime.compare(x.last_seen_at, x.updated_at) == :lt, fail
  end
end
