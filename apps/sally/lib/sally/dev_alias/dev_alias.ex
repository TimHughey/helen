defmodule Sally.DevAlias do
  @moduledoc """
  Database schema definition and functions for the logical representation of
  a specific `Sally.Device` pio.

  All actions (e.g. reading current value, changing state_ on a physical `Sally.Device`
  require a `Sally.DevAlias`
  """

  use Ecto.Schema
  use Alfred, name: [backend: :module], execute: []

  require Logger
  import Ecto.Query, only: [from: 2]

  @type list_or_schema() :: [Ecto.Schema.t(), ...] | Ecto.Schema.t()

  @cmds foreign_key: :dev_alias_id, preload_order: [desc: :sent_at]
  @daps foreign_key: :dev_alias_id, preload_order: [desc: :reading_at]

  @ttl_default 60_000
  schema "dev_alias" do
    field(:name, :string)
    field(:pio, :integer)
    field(:nature, :any, virtual: true)
    field(:description, :string, default: "<none>")
    field(:ttl_ms, :integer, default: @ttl_default)
    field(:register, :any, virtual: true)
    field(:status, :any, virtual: true)
    field(:seen_at, :utc_datetime_usec, virtual: true)

    belongs_to(:device, Sally.Device)
    has_many(:cmds, Sally.Command, @cmds)
    has_many(:datapoints, Sally.Datapoint, @daps)

    timestamps(type: :utc_datetime_usec)
  end

  @returned [returning: true]

  def align_status(%Sally.DevAlias{} = dev_alias, dispatch) do
    %{data: %{pins: pin_data}, recv_at: align_at} = dispatch

    Sally.Command.align_cmd(dev_alias, pin_data, align_at)
  end

  @name_regex ~r/^[a-z~][\w .:-]+[[:alnum:]]$/i
  @pio_validate [greater_than_or_equal_to: 0]
  @ttl_ms_min 50
  @ttl_validate [greater_than_or_equal_to: @ttl_ms_min]
  def changeset(changes, %__MODULE__{} = a, required \\ []) do
    required = changeset_required(required, changes)

    a
    |> Ecto.Changeset.cast(changes, columns(:cast))
    |> Ecto.Changeset.validate_required(required)
    |> Ecto.Changeset.validate_format(:name, @name_regex)
    |> Ecto.Changeset.validate_length(:name, max: 128)
    |> Ecto.Changeset.validate_number(:pio, @pio_validate)
    |> Ecto.Changeset.validate_length(:description, max: 128)
    |> Ecto.Changeset.validate_number(:ttl_ms, @ttl_validate)
    |> Ecto.Changeset.unique_constraint(:name, [:name])
  end

  def changeset_required(what, changes) do
    case what do
      :changes -> Map.keys(changes)
      x when is_atom(x) -> [x]
      x when is_list(x) -> x
      _ -> raise("bad args: #{inspect(what)}")
    end
  end

  @cleanup_defaults [days: -1]
  def cleanup(opts) when is_list(opts) do
    names = names()
    dev_aliases = Enum.map(names, &load_alias(&1))
    cleanup_list = Enum.map(dev_aliases, &cleanup(&1, opts))

    Enum.reject(cleanup_list, &match?({_, 0}, elem(&1, 1))) |> Enum.into(%{})
  end

  def cleanup(%__MODULE__{} = dev_alias, opts) do
    opts = if opts == [], do: @cleanup_defaults, else: opts

    {nature, module} = nature_module(dev_alias)
    cleanup = module.cleanup(dev_alias, opts)

    Sally.Repo.delete(dev_alias)

    {dev_alias.name, {nature, cleanup}}
  end

  @columns [:id, :name, :pio, :description, :ttl_ms, :device_id, :inserted_at, :updated_at]
  @required [:device_id, :name, :pio]

  def columns(:cast), do: @columns
  def columns(:required), do: @required

  def create(%Sally.Device{} = device, opts) do
    dev_alias = Ecto.build_assoc(device, :aliases)
    nature = Sally.Device.nature(device)

    %{
      name: opts[:name],
      pio: opts[:pio],
      description: opts[:description] || dev_alias.description,
      ttl_ms: opts[:ttl_ms] || dev_alias.ttl_ms
    }
    |> changeset(dev_alias)
    |> Sally.Repo.insert!(insert_opts())
    |> then(fn dev_alias -> struct(dev_alias, seen_at: dev_alias.updated_at, nature: nature) end)
  end

  def delete(%{id: _device_id, aliases: _} = device) do
    aliases = load_aliases(device)

    Enum.reduce(aliases, %{}, fn %{name: name} = dev_alias, acc ->
      {nature, module} = nature_module(dev_alias)

      nature_ids = nature_ids_query(dev_alias) |> Sally.Repo.all()

      purged = if nature_ids != [], do: module.purge(nature_ids, []), else: 0
      unregister = unregister(dev_alias)

      Sally.Repo.delete(dev_alias)

      Map.put(acc, name, %{nature => purged, :unregister => unregister})
    end)
  end

  def delete(what) do
    dev_alias = load_alias(what)

    unless match?(%{id: _}, dev_alias), do: raise("not found: #{inspect(what)}")

    {nature, module} = nature_module(dev_alias)

    nature_ids = nature_ids_query(dev_alias) |> Sally.Repo.all()
    purged = module.purge(nature_ids, [])
    unregister = unregister(dev_alias)

    Sally.Repo.delete(dev_alias)

    {:ok, %{:name => dev_alias.name, nature => purged, :unregister => unregister}}
  end

  @doc false
  @impl true
  def execute_cmd(%Alfred.Status{} = status, opts) do
    Alfred.Status.raw(status) |> execute_cmd(opts)
  end

  def execute_cmd(%{name: name} = dev_alias, opts) do
    opts = Keyword.put_new(opts, :name, name)
    new_cmd = Sally.Command.add(dev_alias, opts)

    rc = if(new_cmd.acked, do: :ok, else: :busy)

    preloads = [dev_alias: [device: [:host]]]
    Sally.Repo.preload(new_cmd, preloads) |> Sally.Command.Payload.send_cmd(opts)

    {rc, new_cmd}
  end

  def find(id) when is_integer(id), do: Sally.Repo.get_by(__MODULE__, id: id)
  def find(<<_::binary>> = name), do: Sally.Repo.get_by(__MODULE__, name: name)

  @info_defaults [:summary]
  def info(:defaults), do: @info_defaults

  @info_preload [preload: :device_and_host]
  @info_opt_error "opts must be :summary || :raw || []"
  def info(<<_::binary>> = name, opts) do
    dev_alias = load_alias(name) |> status_lookup(@info_preload)

    return = List.first(opts, :summary)

    cond do
      return == :summary ->
        {_nature, nature_module} = nature_module(dev_alias)

        base = Map.take(dev_alias, summary(:keys))
        device = Map.take(dev_alias.device, Sally.Device.summary(:keys))
        host = Map.take(dev_alias.device.host, Sally.Host.summary(:keys))
        status = Map.take(dev_alias.status, nature_module.summary(:keys))

        Map.merge(base, %{device: device, host: host, status: status})

      return == :raw ->
        dev_alias || {:not_found, name}

      true ->
        raise(@info_opt_error)
    end
  catch
    _kind, :function_clause ->
      {:not_found, name}
  end

  @dont_replace [:id, :last_seen_at, :updated_at]
  @replace Enum.reject(@columns, fn x -> x in @dont_replace end)
  @insert_opts [on_conflict: {:replace, @replace}, conflict_target: [:name]] ++ @returned
  def insert_opts, do: @insert_opts

  def load_alias(what) do
    load_alias_query(what)
    |> Sally.Repo.one()
    |> nature_to_atom()
  end

  def load_aliases(what) do
    load_alias_query(what)
    |> Sally.Repo.all()
    |> nature_to_atom()
  end

  def load_alias_query(field, val) when is_atom(field) do
    load_alias_query({field, val})
  end

  @nature_sql "case when ? then 'cmds' else 'datapoints' end"
  def load_alias_query(what) do
    {field, val} = what_field(what)

    from(dev_alias in __MODULE__,
      where: field(dev_alias, ^field) == ^val,
      order_by: [asc: dev_alias.pio],
      # NOTE: join on device to get mutable
      join: device in Sally.Device,
      on: device.id == dev_alias.device_id,
      # NOTE: select merge the nature
      select_merge: %{nature: fragment(@nature_sql, device.mutable), seen_at: dev_alias.updated_at}
    )
  end

  def names do
    from(x in __MODULE__, select: x.name, order_by: x.name) |> Sally.Repo.all() |> Enum.sort()
  end

  def names_begin_with(pattern) when is_binary(pattern) do
    like_string = "#{pattern}%"

    from(x in __MODULE__, where: like(x.name, ^like_string), order_by: x.name, select: x.name)
    |> Sally.Repo.all()
  end

  def names_query(type) do
    mutable = type == :mut

    devices_query = from(device in Sally.Device, where: device.mutable == ^mutable)

    from(dev_alias in Sally.DevAlias,
      join: device in subquery(devices_query),
      on: device.id == dev_alias.device_id,
      select: dev_alias.name
    )
  end

  def nature_ids_query(what, opts \\ []) when is_list(opts) do
    dev_alias = load_alias(what)

    unless match?(%{id: _}, dev_alias), do: raise("not found: #{inspect(what)}")

    case dev_alias do
      %{id: id, nature: :cmds} -> Sally.Command.ids_query([dev_alias_id: id] ++ opts)
      %{id: id, nature: :datapoints} -> Sally.Datapoint.ids_query([dev_alias_id: id] ++ opts)
    end
  end

  # NOTE: accepts a list, single dev alias or nil
  @natures [:cmds, :datapoints]
  def nature_to_atom(dev_alias) do
    case dev_alias do
      %{nature: <<_::binary>> = x} -> struct(dev_alias, nature: String.to_atom(x))
      %{nature: x} when x in @natures -> dev_alias
      many when is_list(many) -> Enum.map(many, &nature_to_atom(&1))
      nil -> nil
      x -> raise("unable to determine nature: #{inspect(x)}")
    end
  end

  def nature_module(%{nature: nature}) do
    unless nature in @natures, do: raise("unknown nature: #{inspect(nature)}")

    case nature do
      :cmds -> Sally.Command
      :datapoints -> Sally.Datapoint
    end
    |> then(fn module -> {nature, module} end)
  end

  def rename(opts) when is_list(opts) do
    with {:opts, from} when is_binary(from) <- {:opts, opts[:from]},
         {:opts, to} when is_binary(to) <- {:opts, opts[:to]},
         {:found, %{id: _} = x} <- {:found, find(from)},
         cs <- changeset(%{name: to}, x, [:name]),
         {:ok, %{id: _} = updated} <- Sally.Repo.update(cs, returning: true) do
      updated
    else
      {:opts, _} -> {:bad_args, opts}
      {:found, nil} -> {:not_found, opts[:from]}
      {:error, %Ecto.Changeset{} = cs} -> {:name_taken, cs.changes.name}
    end
  end

  @impl true
  def status_lookup(%{name: name, nature: nature}, opts) do
    case nature do
      :cmds -> Sally.Command.status(name, opts)
      :datapoints -> Sally.Datapoint.status(name, opts)
    end
    |> status_finalize()
  end

  # NOTE: nature is set by the status queries
  def status_finalize(dev_alias) do
    case dev_alias do
      # NOTE: populate nature from the original reuqest map
      %{status: %{}, nature: nature} when is_atom(nature) -> dev_alias
      _ -> {:error, :no_data}
    end
  end

  def summary(:keys), do: [:name, :pio, :description, :ttl_ms]

  def ttl_adjust(what, ttl_ms) do
    changes = %{ttl_ms: ttl_ms}
    dev_alias = load_alias(what)

    # NOTE: update!/2 will raise so matching on result is safe
    # NOTE: reload DevAlias to ensure nature and seen_at are populated
    changeset(changes, dev_alias, :ttl_ms)
    |> Sally.Repo.update!([])
    |> load_alias()
  end

  def ttl_reset(%{nature: nature} = dev_alias, ttl_at) when nature in @natures do
    unless match?(%DateTime{}, ttl_at), do: raise("ttl_at not a DateTime")

    changes = %{updated_at: ttl_at}

    # NOTE: Sally.Repo.update!/2 returns virtual fields unchanged
    dev_alias = changeset(changes, dev_alias, :changes) |> Sally.Repo.update!(@returned)

    struct(dev_alias, seen_at: dev_alias.updated_at)
  end

  # NOTE: generic ttl_reset (e.g. cmd_ack)
  def ttl_reset(what, ttl_at) do
    load_alias(what) |> ttl_reset(ttl_at)
  end

  def what_field(what) do
    case what do
      %__MODULE__{id: id} -> {:id, id}
      %Sally.Device{id: device_id} -> {:device_id, device_id}
      %{dev_alias_id: id} -> {:id, id}
      [{field, _val} = tuple] when is_atom(field) -> tuple
      <<_::binary>> -> {:name, what}
      x when is_integer(x) -> {:id, what}
      _ -> raise("bad args: #{inspect(what)}")
    end
  end
end
