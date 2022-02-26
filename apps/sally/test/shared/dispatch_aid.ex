defmodule Sally.DispatchAid do
  @moduledoc """
  Supporting functionality for creating Sally.Dispatch for testing
  """

  @tz "America/New_York"

  defmacro assert_processed(dispatch) do
    quote bind_quoted: [dispatch: dispatch] do
      assert %Sally.Dispatch{halt_reason: :none, results: %{} = results} = dispatch
      assert %{device: %Sally.Device{}, aliases: aliases} = results

      nature = if(dispatch.subsystem == "mut", do: :cmds, else: :datapoints)

      Enum.each(List.wrap(aliases), fn dev_alias ->
        assert %Sally.DevAlias{name: name} = dev_alias
        assert %{name: ^name, nature: ^nature} = Alfred.name_info(name)
      end)

      dispatch
    end
  end

  # @sent_at_shift [milliseconds: -2]
  def add(opts) when is_list(opts) do
    {fields, opts_rest} = split_opts(opts, :fields)

    dispatch = Sally.Dispatch.new(fields)
    opts_map = assemble_opts_map(opts_rest)

    case dispatch do
      %{subsystem: "host"} -> Sally.HostAid.dispatch(dispatch, opts_map)
      %{subsystem: "immut"} -> Sally.DatapointAid.dispatch(dispatch, opts_map)
      %{subsystem: "mut"} -> Sally.CommandAid.dispatch(dispatch, opts_map)
    end
    # NOTE: a keyword list of fields is produced above
    |> finalize(dispatch, opts_map)
  end

  def add(%{dispatch_add: dispatch_opts} = ctx) when is_list(dispatch_opts) do
    dev_alias_opts = Map.take(ctx, [:dev_alias_opts]) |> Enum.into([])

    dispatch_opts = Keyword.merge(dispatch_opts, dev_alias_opts)
    dispatch = add(dispatch_opts)

    %{dispatch: dispatch, dispatch_filter: make_filter(dispatch)}
  end

  def add(_), do: :ok

  @create_opts [:host, :dev_alias_opts, :device]
  def assemble_opts_map(opts) when is_list(opts) do
    {create_opts, opts_rest} = Keyword.split(opts, @create_opts)

    case create_opts do
      [{:host, host_opts}] -> %{host: Sally.HostAid.add(host_opts)}
      [{:dev_alias_opts, dev_alias_opts}] -> Sally.DevAliasAid.add(dev_alias_opts)
      [{:device, device_opts}] -> Sally.DeviceAid.add(device_opts)
      x -> raise_opts_map("ambiguous opts", x)
    end
    # NOTE: all functions in the above case statement return a map
    |> Map.merge(Enum.into(opts_rest, %{}))
    |> Map.put(:opts, opts_rest)
  end

  def finalize(fields, dispatch, opts_map) do
    dispatch
    |> Sally.Dispatch.update(ident: host_ident(opts_map), txn_info: opts_map)
    |> finalize_data(fields, opts_map)
  end

  def finalize_data(dispatch, fields, opts_map) do
    {data, fields_rest} = Keyword.pop(fields, :data, :none)
    {payload, fields_rest} = Keyword.pop(fields_rest, :payload, :none)

    if data == :none, do: raise(":data field missing")
    unless payload == :none, do: IO.warn(":payload field ignored")

    mtime = Timex.now() |> DateTime.to_unix(:millisecond)
    # NOTE: default to echo the dispatch, use echo: false to disable
    echo = Map.get(opts_map, :echo, :dispatch)
    common_data = %{echo: echo, mtime: mtime}
    data = Map.merge(data, common_data)

    # NOTE: must use iodata: false to replicate incoming MQTT payload
    payload = Msgpax.pack!(data, iodata: false)

    Sally.Dispatch.update(dispatch, [data: data, payload: payload] ++ fields_rest)
  end

  def host_ident(opts_map) do
    case opts_map do
      %{host: %{ident: x}} -> x
      %{host: <<_::binary>> = x} -> x
      _ -> raise("unable to discover host ident")
    end
  end

  @filter_keys [:test, :r2, :ident, :subsystem, :category, :filter_extra]
  def make_filter(%Sally.Dispatch{} = dispatch) do
    Enum.map(@filter_keys, fn
      filter when is_map_key(dispatch, filter) -> Map.get(dispatch, filter)
      filter -> Atom.to_string(filter)
    end)
    |> List.flatten()
  end

  def raise_opts_map(binary, opts_map) do
    [binary, "\n", inspect(opts_map, pretty: true)] |> IO.iodata_to_binary() |> raise()
  end

  @field_opts [:category, :env, :opts, :recv_at, :sent_at, :subsystem]
  def split_opts(opts, :fields) do
    now = Timex.now(@tz)
    defaults = [env: "test", sent_at: now, recv_at: now]
    {field_opts, opts_rest} = Keyword.split(opts, @field_opts)

    opts_rest = Keyword.put_new(opts_rest, :ref_dt, now)

    {Keyword.merge(defaults, field_opts), opts_rest}
  end
end
