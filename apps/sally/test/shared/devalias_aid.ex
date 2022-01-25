defmodule Sally.DevAliasAid do
  @moduledoc """
  Supporting functionality for creating Sally.DevAlias for testing
  """

  defmacrop collect(val) do
    quote bind_quoted: [val: val] do
      acc = var!(acc)
      key = var!(key)

      case acc do
        acc when is_map(acc) -> Map.put(acc, key, val)
        acc when is_list(acc) -> Keyword.put(acc, key, val)
      end
    end
  end

  @add_order [:prereqs, :count, :cmds, :daps]
  @return_keys [:host, :device, :dev_alias, :name_registration, :cmd_latest, :dap_history]
  def add(%{dev_alias_add: opts} = ctx) when is_list(opts) do
    {ctrl_map, opts} = normalize_opts(opts, :as_map)

    Enum.reduce(@add_order, ctrl_map, fn
      :prereqs, acc -> prereqs(acc, ctx)
      :count, %{count: 1} = acc -> add_one(acc, opts)
      :count, %{count: _} = acc -> add_many(acc, opts)
      :cmds, %{cmds: cmd_args} = acc when is_list(cmd_args) -> add_cmds(acc, cmd_args)
      :daps, %{daps: dp_args} = acc when is_list(dp_args) -> add_datapoints(acc, dp_args)
      _no_match, acc -> acc
    end)
    |> Map.take(@return_keys)
  end

  def add(%{devalias_add: opts} = ctx) do
    Map.drop(ctx, [:devalias_add])
    |> Map.put(:dev_alias_add, opts)
    |> add()
  end

  def add(opts) when is_list(opts), do: %{devalias_add: opts} |> add()

  def add(_), do: :ok

  @add_cmds_order [:cmd_history, :cmd_latest]
  def add_cmds(%{cmds: cmd_opts} = ctrl_map, opts) do
    cmd_map = Enum.into(cmd_opts, %{})
    opts_map = Enum.into(opts, %{}) |> Map.put(:_cmds_, cmd_map)

    Enum.reduce(@add_cmds_order, ctrl_map, fn
      # NOTE: must use acc for collect/1 macro
      :cmd_history = key, acc -> make_historical(:cmds, ctrl_map, opts_map) |> collect()
      :cmd_latest = key, acc -> make_pending(ctrl_map, opts_map) |> collect()
      _, ctrl_map -> ctrl_map
    end)
  end

  @add_datapoints_order [:dap_history]
  def add_datapoints(ctrl_map, opts) do
    opts_map = Enum.into(opts, %{})

    Enum.reduce(@add_datapoints_order, ctrl_map, fn
      # NOTE: must use acc for collect/1 macro
      :dap_history = key, acc -> make_historical(:daps, ctrl_map, opts_map) |> collect()
      _, ctrl_map -> ctrl_map
    end)
  end

  @add_one_keys [:name, :nature, :description, :pio, :ttl_ms]
  @add_one_opts Enum.map(@add_one_keys, fn key -> {key, :auto} end)
  def add_one(%Sally.Device{} = device, opts) when is_list(opts) do
    opts_map = Enum.into(opts, %{})

    Enum.reduce(@add_one_opts, [], fn
      {key, val}, acc when is_map_key(opts_map, key) -> collect(val)
      {:name = key, :auto}, acc -> unique(:dev_alias) |> collect()
      {:description = key, :auto}, acc -> description() |> collect()
      {:nature = key, :auto}, acc -> if(device.mutable, do: :cmds, else: :datapoints) |> collect()
      {:pio = key, :auto}, acc -> Sally.DeviceAid.next_pio(device) |> collect()
      {:ttl_ms = key, :auto}, acc -> collect(15_000)
      {_key, _val}, acc -> acc
    end)
    |> then(fn params -> Sally.DevAlias.create(device, params) |> register(opts) end)
  end

  def add_one(%{device: device} = ctrl_map, opts) do
    created_map = add_one(device, opts)

    Map.merge(ctrl_map, created_map)
  end

  def add_many(%{count: count, device: device} = ctrl_map, opts) do
    dev_aliases = Enum.map(1..count, fn _ -> add_one(device, opts) |> Map.get(:dev_alias) end)

    Map.put(ctrl_map, :dev_alias, dev_aliases)
  end

  @defaults %{prereqs: true, count: 1, cmds: false, daps: false}
  def ensure_keywords(opts) do
    Enum.reduce(opts, @defaults, fn
      {key, val}, acc -> Map.put(acc, key, val)
      key, acc when is_atom(key) -> Map.put(acc, key, true)
      key, acc -> unknown_opt(key, opts, acc)
    end)
  end

  def find_pending([%Sally.DevAlias{} | _] = dev_aliases) do
    Enum.find(dev_aliases, fn %{name: name} -> match?(%{rc: :pending}, Alfred.status(name, [])) end)
  end

  def find_pending(_dev_aliases), do: raise("not a list of Sally.DevAlias")

  def description do
    Ecto.UUID.generate() |> String.replace("-", " ")
  end

  def make_historical(:cmds, %Sally.DevAlias{} = dev_alias, opts_map) do
    Sally.CommandAid.historical(dev_alias, opts_map)
  end

  def make_historical(:daps, %Sally.DevAlias{} = dev_alias, opts_map) do
    Sally.DatapointAid.historical(dev_alias, opts_map)
  end

  def make_historical(what, ctrl_map, %{history: _} = opts_map) do
    case ctrl_map do
      %{dev_alias: x} when is_list(x) ->
        Enum.map(x, fn dev_alias -> make_historical(what, dev_alias, opts_map) end)

      %{dev_alias: %Sally.DevAlias{} = dev_alias} ->
        make_historical(what, dev_alias, opts_map)

      ctrl_map ->
        raise("can make historical:\n#{inspect(ctrl_map, pretty: true)}")
    end
  end

  def make_historical(_what, ctrl_map, _opts_map), do: ctrl_map

  @pending %{latest: :pending}
  def make_pending(%{dev_alias: dev_alias}, %{_cmds_: cmd_args}) do
    dev_aliases = List.wrap(dev_alias)

    case cmd_args do
      @pending -> Enum.map(dev_aliases, &make_pending(&1, cmd_args))
      _ -> []
    end
  end

  def make_pending(%Sally.DevAlias{name: name}, cmd_args) do
    echo_opts = Map.take(cmd_args, [:echo]) |> Enum.into([])
    cmd_opts = [cmd: random_cmd(), name: name, cmd_opts: [ack: :host]]

    Alfred.execute(cmd_opts, echo_opts)
    |> sleep(10)
  end

  def make_pending(ctrl_map, _cmd_args), do: ctrl_map

  def normalize_opts(opts, :as_map) do
    opts_map = ensure_keywords(opts)

    {ctrl_map, opts_rest} = Map.split(opts_map, Map.keys(@defaults))
    ctrl_map = Map.put(ctrl_map, :opts, Enum.into(opts_rest, []))
    {ctrl_map, Enum.into(opts_rest, [])}
  end

  # NOTE: returns updated ctrl_map
  def prereqs(%{prereqs: true, opts: opts} = ctrl_map, _ctx) do
    {device_opts, opts_rest} = Sally.DeviceAid.split_opts(opts)
    {host_opts, _opts_rest} = Sally.HostAid.split_opts(opts_rest)
    # NOTE: unless otherwise specified, always setup the host
    host_opts = Keyword.put_new(host_opts, :setup, true)

    host = Sally.HostAid.add(host_opts)

    %{device: device} = Sally.DeviceAid.add(%{device_add: device_opts, host: host})

    Map.merge(ctrl_map, %{host: host, device: device})
  end

  # NOTE: returns ctrl_map
  def prereqs(%{prereqs: false} = ctrl_map, %{host: host, device: device}) do
    Map.merge(ctrl_map, %{host: host, device: device})
  end

  def prereqs(_, _), do: raise(":device and/or :host not found in ctx")

  @provides [:host, :device, :dev_alias, :cmd_latest, :name_registration]
  def provided_opts(ctx), do: Map.take(ctx, @provides) |> Enum.into([])

  def random_cmd, do: Ecto.UUID.generate() |> String.split("-") |> Enum.at(1)

  def random_pick([%Sally.DevAlias{} | _] = dev_aliases, count \\ 1) do
    picked = Enum.take_random(dev_aliases, count)

    if count == 1, do: List.first(picked), else: picked
  end

  def register({:ok, %Sally.DevAlias{device_id: device_id}} = dev_alias_rc, opts) do
    case Sally.Device.find(device_id) do
      %{mutable: true} -> :cmds
      %{mutable: false} -> :datapoints
      error -> raise(inspect(error, pretty: true))
    end
    |> then(fn nature -> register(dev_alias_rc, nature, opts) end)
  end

  def register({:ok, %Sally.DevAlias{} = dev_alias}, nature, opts) do
    register_opts = Keyword.get(opts, :register, [])

    if register_opts do
      allowed_opts = Alfred.Name.allowed_opts()
      register_opts = Keyword.take(opts, allowed_opts) |> Keyword.put_new(:nature, nature)

      rc = Sally.DevAlias.just_saw(dev_alias, register_opts)

      %{dev_alias: dev_alias, name_registration: %{rc: rc, name: dev_alias.name, nature: nature}}
    else
      %{dev_alias: dev_alias, name_registration: :none}
    end
  end

  def register(error, _nature, _opts), do: raise(inspect(error, pretty: true))

  def sleep(pass, ms), do: tap(pass, fn _ -> Process.sleep(ms) end)

  def unique(x) when x in [:devalias, :dev_alias] do
    x = Ecto.UUID.generate() |> String.split("-") |> Enum.at(4)

    ["devalias_", x] |> IO.iodata_to_binary()
  end

  def unknown_opt(key, opts, acc) do
    ["unknown opt: [", inspect(key), "] in ", inspect(opts)] |> IO.iodata_to_binary() |> raise()

    acc
  end
end
