defmodule Sally.DispatchAid do
  @moduledoc """
  Supporting functionality for creating Sally.Dispatch for testing
  """

  @tz "America/New_York"

  @sent_at_shift [milliseconds: -2]
  def add(%{dispatch_add: opts} = ctx) when is_list(opts) do
    {now, opts_rest} = Keyword.pop(opts, :ref_dt, Timex.now(@tz))
    {sent_at, opts_rest} = Keyword.pop(opts_rest, :sent_at, now)
    {recv_at, opts_rest} = Keyword.pop(opts_rest, :recv_at, now)
    {subsystem, opts_rest} = Keyword.pop(opts_rest, :subsystem)
    {category, opts_rest} = Keyword.pop(opts_rest, :category)
    {callback_opt, _opts_rest} = Keyword.pop(opts_rest, :callback, String.to_atom(subsystem))

    callback_mod = callback_mod(callback_opt)

    fields = [
      env: "test",
      subsystem: subsystem,
      category: category,
      sent_at: Timex.shift(sent_at, @sent_at_shift),
      recv_at: recv_at,
      # NOTE: must simulate routed rc and valid?
      routed: :ok,
      valid?: true,
      invalid_reason: :none
    ]

    dispatch = Sally.Dispatch.new(fields)

    case dispatch do
      %Sally.Dispatch{subsystem: "host", category: "boot"} -> add_host(dispatch, ctx, :boot)
      %Sally.Dispatch{subsystem: "host", category: "startup"} -> add_host(dispatch, ctx, :startup)
      %Sally.Dispatch{subsystem: "immut", category: "celsius"} -> add_immutable(dispatch, ctx)
      %Sally.Dispatch{subsystem: "immut", category: "relhum"} -> add_immutable(dispatch, ctx)
      %Sally.Dispatch{subsystem: "mut", category: "cmdack"} -> add_mutable_cmdack(dispatch, ctx)
      %Sally.Dispatch{subsystem: "mut", category: "status"} -> add_mutable(dispatch, ctx)
    end
    |> Sally.Message.Handler.Server.process(callback_mod)
    |> then(fn dispatch -> %{dispatch: dispatch} end)
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
    |> then(fn fields -> struct(base, fields) end)
  end

  # (1 of x) create a Sally.Dispatch for a host startup
  def add_host(base, %{dispatch_add: opts} = ctx, :startup) do
    host_ident = if ctx[:host], do: ctx.host.ident, else: Sally.HostAid.unique(:ident)

    [ident: host_ident, payload: Sally.HostAid.make_payload(:startup, opts)]
    |> then(fn fields -> struct(base, fields) end)
  end

  def add_immutable(base, %{dispatch_add: opts} = ctx) do
    status = opts[:status] || "ok"
    data = if(opts[:data], do: opts[:data], else: %{}) |> Map.merge(%{metrics: %{"read" => 3298}})
    fields = [filter_extra: [ctx.device.ident, status], data: data]

    add_known_host(base, ctx) |> struct(fields)
  end

  # def add_immutable(_), do: :ok

  def add_mutable(base, %{dispatch_add: opts} = ctx) do
    status = opts[:status] || "ok"
    cmd = opts[:cmd] || "on"
    pin_count = ctx.device.pios
    data = Map.merge(%{pins: make_pins(pin_count, cmd)}, opts[:data] || %{})

    fields = [filter_extra: [ctx.device.ident, status], data: data]

    add_known_host(base, ctx) |> struct(fields)
  end

  @sent_at_shift [microseconds: -333]
  def add_mutable_cmdack(%{sent_at: sent_at} = base, %{dispatch_add: opts} = ctx) do
    {cmd_add_opts, opts_rest} = Keyword.split(opts, [:cmd, :cmd_opts])
    {track_cmd, opts_rest} = Keyword.pop(opts_rest, :track, true)

    sent_at = Timex.shift(sent_at, @sent_at_shift)
    cmd_add_opts = Keyword.merge([cmd: "on", sent_at: sent_at], cmd_add_opts)
    cmd = Sally.Command.add(ctx.dev_alias, cmd_add_opts)
    if(track_cmd, do: Sally.Command.track(cmd, opts_rest))

    refid = cmd.refid
    fields = [filter_extra: [refid], data: opts[:data] || %{}]
    add_known_host(base, ctx) |> struct(fields)
  end

  ##
  ## Callback handling
  ##

  def callback_mod(what) do
    case what do
      :none -> __MODULE__
      :mut -> Sally.Mutable.Handler
      :immut -> Sally.Immutable.Handler
      :host -> Sally.Host.Handler
    end
  end

  def process(dispatch), do: dispatch
  def post_process(dispatch), do: dispatch

  ##
  ## Test Assistance
  ##

  defmacro assert_processed(dispatch) do
    quote location: :keep, bind_quoted: [dispatch: dispatch] do
      assert %Sally.Dispatch{valid?: true, invalid_reason: :none, results: %{} = results} = dispatch
      assert %{device: %Sally.Device{}, aliases: aliases} = results

      nature = if(dispatch.subsystem == "mut", do: :cmds, else: :datapoints)

      Enum.each(List.wrap(aliases), fn dev_alias ->
        assert %Sally.DevAlias{name: name} = dev_alias
        assert %{name: ^name, nature: ^nature} = Alfred.name_info(name)
      end)

      dispatch
    end
  end

  defp add_known_host(base, ctx), do: struct(base, ident: ctx.host.ident, host: ctx.host)

  defp make_pins(count, cmd), do: for(pin <- 0..(count - 1), do: [pin, cmd])
end
