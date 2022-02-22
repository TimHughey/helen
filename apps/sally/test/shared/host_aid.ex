defmodule Sally.HostAid do
  @moduledoc """
  Supporting functionality for creating Sally.Host for testing
  """

  defmacrop put_host(val) do
    quote bind_quoted: [val: val] do
      Map.put(var!(ctrl_map), :host, val)
    end
  end

  # NOTE: ExUnit.Case setup function
  def add(%{host_add: opts}), do: %{host: add(opts)}

  @add_order [:ident_only, :create, :setup]
  def add(opts) when is_list(opts) do
    {ctrl_map, opts} = split_opts(opts, :ctrl_map)

    Enum.reduce(@add_order, ctrl_map, fn
      _action, %{ident_only: true, host: <<_::binary>>} = ctrl_map -> ctrl_map
      :ident_only, %{ident_only: true} = ctrl_map -> unique(:ident) |> put_host()
      :create, %{create: true} = ctrl_map -> add_one(opts) |> put_host()
      :setup, %{setup: true, host: host} = ctrl_map -> setup(host, opts) |> put_host()
      _action, ctrl_map -> ctrl_map
    end)
    |> Map.get(:host)
  end

  def add(_ctx), do: :ok

  def add_one(opts) when is_list(opts) do
    ident = unique(:ident)

    changes = %{
      ident: ident,
      name: ident,
      firmware_vsn: "00.01.00",
      idf_vsn: "v4.4-beta1",
      app_sha: "0123456789ab",
      build_at: Timex.now() |> Timex.shift(minutes: -5),
      start_at: Keyword.get(opts, :start_at, Timex.now()),
      reset_reason: "esp_restart",
      seen_at: Keyword.get(opts, :seen_at, Timex.now())
    }

    changeset = Sally.Host.changeset(changes)
    replace_cols = Map.keys(changes)
    insert_opts = Sally.Host.insert_opts(replace_cols)

    case Sally.Repo.insert(changeset, insert_opts) do
      {:ok, %{} = host} -> host
      error -> raise(inspect(error, pretty: true))
    end
  end

  def dispatch(%{category: "boot"}, opts_map) do
    data = %{elapsed_ms: 5981, tasks: 12, stack: %{size: 4096, highwater: 1024}}

    profile = profile_from_opts(opts_map)

    [filter_extra: [profile], data: data]
  end

  def dispatch(%{category: "run"}, _opts_map) do
    data = %{
      ap: %{pri_chan: 11, rssi: -54},
      heap: %{min: 161_000, max_alloc: 65_536, free: 158_000}
    }

    [filter_extra: [], data: data]
  end

  def dispatch(%{category: "startup"}, _opts_map) do
    data = %{
      firmware_vsn: "00.00.00",
      idf_vsn: "v4.3.1",
      app_sha: "01abcdef",
      build_date: "Jul  1 2021",
      build_time: "13:23:00",
      reset_reason: "power on"
    }

    [filter_extra: [], data: data]
  end

  def profile_from_opts(opts_map) do
    case opts_map do
      %{host: %{profile: profile}} -> profile
      %{host: <<_::binary>>} -> "generic"
      _ -> raise("unable to discover profile")
    end
  end

  defmacro put_ctrl_map(val) do
    quote bind_quoted: [val: val] do
      {Map.put(var!(ctrl_map), var!(key), val), var!(opts_rest)}
    end
  end

  defmacro put_opts_rest(val) do
    quote bind_quoted: [val: val] do
      {var!(ctrl_map), Keyword.put(var!(opts_rest), var!(key), val)}
    end
  end

  @default_ctrl_map %{ident_only: false, create: true, setup: true}
  def split_opts(opts, :ctrl_map) do
    Enum.reduce(opts, {@default_ctrl_map, _opts_rest = []}, fn
      {key, val}, {ctrl_map, opts_rest} when is_map_key(ctrl_map, key) -> put_ctrl_map(val)
      key, {ctrl_map, opts_rest} when is_map_key(ctrl_map, key) -> put_ctrl_map(true)
      {key, val}, {ctrl_map, opts_rest} when is_atom(key) -> put_opts_rest(val)
      key, {_ctrl_map, _opts_rest} -> unknown_opt(key, opts)
    end)
  end

  def setup(%Sally.Host{} = host, opts) do
    name = opts[:name] || unique(:name)
    profile = opts[:profile] || "generic"

    case Sally.Host.setup(host, name: name, profile: profile) do
      {:ok, %Sally.Host{} = host} -> host
      error -> raise(inspect(error, pretty: true))
    end
  end

  def setup(_ctx), do: :ok

  # NOTE: for use by other Sally test aid mdules
  def split_opts(opts), do: Keyword.split(opts, supported_opts())
  def supported_opts, do: [:profile, :start_at, :seen_at, :setup]

  def unique(what) when is_atom(what) do
    unique = Ecto.UUID.generate() |> String.split("-") |> Enum.at(4)

    case what do
      :ident -> "host.#{unique}"
      :name -> "hostname_#{unique}"
    end
  end

  def unknown_opt(key, opts) do
    ["unknown opt: [", inspect(key), "] in ", inspect(opts)] |> IO.iodata_to_binary() |> raise()
  end
end
