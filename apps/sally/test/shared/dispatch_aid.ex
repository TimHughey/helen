defmodule Sally.DispatchAid do
  @moduledoc """
  Supporting functionality for creating Sally.Dispatch for testing
  """

  def add(%{dispatch_add: opts} = ctx) when is_list(opts) do
    fields = [
      env: "test",
      subsystem: opts[:subsystem],
      category: opts[:category],
      sent_at: sent_at(opts),
      recv_at: recv_at(opts)
    ]

    case struct(Sally.Dispatch, fields) do
      %Sally.Dispatch{subsystem: "host", category: "boot"} = x -> add_host(x, ctx, :boot)
      %Sally.Dispatch{subsystem: "host", category: "startup"} = x -> add_host(x, ctx, :startup)
      %Sally.Dispatch{subsystem: "immut", category: "celsius"} = x -> add_immutable(x, ctx)
      %Sally.Dispatch{subsystem: "immut", category: "relhum"} = x -> add_immutable(x, ctx)
      %Sally.Dispatch{subsystem: "mut", category: "cmdack"} = x -> add_mutable_cmdack(x, ctx)
      %Sally.Dispatch{subsystem: "mut", category: "status"} = x -> add_mutable(x, ctx)
      %Sally.Dispatch{} -> :ok
    end
    |> preprocess()
  end

  def add(_), do: :ok

  # (2 of x) create a Sally.Dispatch for a host boot messgge
  def add_host(base, %{dispatch_add: opts} = ctx, :boot) do
    host_ident = if ctx[:host], do: ctx.host.ident, else: Sally.HostAid.unique(:ident)
    host_profile = if ctx[:host], do: ctx.host.profile, else: "generic"

    [
      ident: host_ident,
      payload: Sally.HostAid.make_payload(:startup, opts),
      filter_extra: [host_profile]
    ]
    |> then(fn fields -> %{dispatch: struct(base, fields)} end)
  end

  # (1 of x) create a Sally.Dispatch for a host startup
  def add_host(base, %{dispatch_add: opts} = ctx, :startup) do
    host_ident = if ctx[:host], do: ctx.host.ident, else: Sally.HostAid.unique(:ident)

    [ident: host_ident, payload: Sally.HostAid.make_payload(:startup, opts)]
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
      base_valid_kv = [valid?: true, invalid_reason: :none]

      assert %Sally.Dispatch{
               valid?: true,
               invalid_reason: :none,
               results: %{device: %Sally.Device{mutable: mutable?}}
               # seen_list: []
               #   seen_list: [_ | _] = seen_list
             } = dispatch = x

      # validate the device processed established appropriate Alfred linkages
      # want_struct = if mutable?, do: Alfred.MutableStatus, else: Alfred.ImmutableStatus

      # Enum.all?(seen_list, fn name -> assert is_struct(Alfred.status(name), want_struct) end)

      # return the processed dispatch
      dispatch
    end
  end

  defp add_known_host(base, ctx), do: struct(base, ident: ctx.host.ident, host: ctx.host)

  defp make_pins(count, cmd), do: for(pin <- 0..(count - 1), do: [pin, cmd])

  defp preprocess(%{dispatch: %Sally.Dispatch{} = x}), do: %{dispatch: Sally.Dispatch.preprocess(x)}
  defp preprocess(any), do: any

  defp recv_at(opts), do: opts[:recv_at] || DateTime.utc_now()

  @shift_opts [milliseconds: -2]
  defp sent_at(opts) do
    Keyword.get(opts, :sent_at, DateTime.utc_now())
    |> Timex.shift(@shift_opts)
  end
end
