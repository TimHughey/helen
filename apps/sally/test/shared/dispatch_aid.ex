defmodule Sally.DispatchAid do
  use Should

  alias Sally.Dispatch
  alias Sally.HostAid

  def add(%{dispatch_add: opts} = ctx) when is_list(opts) do
    fields = [
      env: "test",
      subsystem: opts[:subsystem],
      category: opts[:category],
      sent_at: sent_at(opts),
      recv_at: recv_at(opts)
    ]

    case struct(Dispatch, fields) do
      %Dispatch{subsystem: "host", category: "boot"} = x -> add_host(x, ctx, :boot)
      %Dispatch{subsystem: "host", category: "startup"} = x -> add_host(x, ctx, :startup)
      %Dispatch{subsystem: "immut", category: "celsius"} = x -> add_immutable(x, ctx)
      %Dispatch{subsystem: "immut", category: "relhum"} = x -> add_immutable(x, ctx)
      %Dispatch{subsystem: "mut", category: "cmdack"} = x -> add_mutable_cmdack(x, ctx)
      %Dispatch{subsystem: "mut", category: "status"} = x -> add_mutable(x, ctx)
      %Dispatch{} -> :ok
    end
    |> preprocess()
  end

  def add(_), do: :ok

  # (2 of x) create a Dispatch for a host boot messgge
  def add_host(base, %{dispatch_add: opts} = ctx, :boot) do
    host_ident = if ctx[:host], do: ctx.host.ident, else: Sally.HostAid.unique(:ident)
    host_profile = if ctx[:host], do: ctx.host.profile, else: "generic"

    [
      ident: host_ident,
      payload: HostAid.make_payload(:startup, opts),
      filter_extra: [host_profile]
    ]
    |> then(fn fields -> %{dispatch: struct(base, fields)} end)
  end

  # (1 of x) create a Dispatch for a host startup
  def add_host(base, %{dispatch_add: opts} = ctx, :startup) do
    host_ident = if ctx[:host], do: ctx.host.ident, else: Sally.HostAid.unique(:ident)

    [ident: host_ident, payload: HostAid.make_payload(:startup, opts)]
    |> then(fn fields -> %{dispatch: struct(base, fields)} end)
  end

  def add_immutable(base, %{dispatch_add: opts} = ctx) do
    status = opts[:status] || "ok"
    data = if(opts[:data], do: opts[:data], else: %{}) |> Map.merge(%{metrics: %{"read" => 3298}})
    fields = [filter_extra: [ctx.device.ident, status], data: data]

    %{dispatch: add_known_host(base, ctx) |> struct(fields)}
  end

  def add_immutable(_), do: :ok

  def add_mutable(base, %{dispatch_add: opts} = ctx) do
    status = opts[:status] || "ok"
    cmd = opts[:cmd] || "on"
    pin_count = ctx.device.pios
    data = Map.merge(%{pins: make_pins(pin_count, cmd)}, opts[:data] || %{})

    fields = [filter_extra: [ctx.device.ident, status], data: data]

    %{dispatch: add_known_host(base, ctx) |> struct(fields)}
  end

  def add_mutable_cmdack(base, %{dispatch_add: opts} = ctx) do
    refid = ctx.command.refid
    fields = [filter_extra: [refid], data: opts[:data] || %{}]

    %{dispatch: add_known_host(base, ctx) |> struct(fields)}
  end

  ##
  ## Test Assistance
  ##

  defmacro assert_processed(x) do
    quote location: :keep, bind_quoted: [x: x] do
      alias Sally.{DevAlias, Device}

      base_valid_kv = [valid?: true, invalid_reason: :none]
      dispatch = Should.Be.Struct.with_all_key_value(x, Dispatch, base_valid_kv)

      results = Should.Be.map(dispatch.results)

      device = Should.Be.Map.with_key(results, :device) |> Should.Be.struct(Device)
      seen_list = Should.Be.NonEmpty.list(dispatch.seen_list)

      # validate the device processed established appropriate Alfred linkages
      want_struct = if device.mutable, do: Alfred.MutableStatus, else: Alfred.ImmutableStatus

      for name <- seen_list do
        Alfred.status(name) |> Should.Be.struct(want_struct)
      end

      # return the processed dispatch
      dispatch
    end
  end

  defp add_known_host(base, ctx), do: struct(base, ident: ctx.host.ident, host: ctx.host)

  defp make_pins(count, cmd), do: for(pin <- 0..(count - 1), do: [pin, cmd])

  defp preprocess(%{dispatch: %Dispatch{} = x}), do: %{dispatch: Dispatch.preprocess(x)}
  defp preprocess(any), do: any

  defp recv_at(opts), do: opts[:recv_at] || DateTime.utc_now()

  defp sent_at(opts) do
    shift_opts = [milliseconds: -2]
    opts[:sent_at] || DateTime.utc_now() |> Timex.shift(shift_opts)
  end
end
