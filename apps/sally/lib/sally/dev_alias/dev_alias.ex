defmodule Sally.DevAlias do
  @moduledoc """
  Database schema definition and functions for the logical representation of
  a specific `Sally.Device` pio.

  All actions (e.g. reading current value, changing state_ on a physical `Sally.Device`
  require a `Sally.DevAlias`
  """
  require Logger
  require Ecto.Query

  use Ecto.Schema
  use Alfred, name: [backend: :module], execute: []

  alias __MODULE__, as: Schema
  alias Ecto.Changeset
  alias Sally.{Command, Datapoint, Device, Repo}

  @pio_min 0
  @ttl_default 15_000
  @ttl_min 50

  @type list_or_schema() :: [Ecto.Schema.t(), ...] | Ecto.Schema.t()

  @cmds foreign_key: :dev_alias_id, preload_order: [desc: :sent_at]
  @daps foreign_key: :dev_alias_id, preload_order: [desc: :reading_at]

  schema "dev_alias" do
    field(:name, :string)
    field(:pio, :integer)
    field(:nature, :any, virtual: true)
    field(:description, :string, default: "<none>")
    field(:ttl_ms, :integer, default: @ttl_default)
    field(:register, :any, virtual: true)
    field(:status, :any, virtual: true)
    field(:seen_at, :utc_datetime_usec, virtual: true)

    belongs_to(:device, Device)
    has_many(:cmds, Command, @cmds)
    has_many(:datapoints, Datapoint, @daps)

    timestamps(type: :utc_datetime_usec)
  end

  @returned [returning: true]

  def align_status(%Sally.DevAlias{} = dev_alias, dispatch) do
    %{data: %{pins: pin_data}, recv_at: align_at} = dispatch

    Sally.Command.align_cmd(dev_alias, pin_data, align_at)
  end

  def changeset(changes, %Schema{} = a, opts \\ []) do
    a
    |> Changeset.cast(changes, columns(:cast))
    |> Changeset.validate_required(opts[:required] || columns(:required))
    |> Changeset.validate_format(:name, ~r/^[a-z~][\w .:-]+[[:alnum:]]$/i)
    |> Changeset.validate_length(:name, max: 128)
    |> Changeset.validate_number(:pio, greater_than_or_equal_to: @pio_min)
    |> Changeset.validate_length(:description, max: 128)
    |> Changeset.validate_number(:ttl_ms, greater_than_or_equal_to: @ttl_min)
    |> Changeset.unique_constraint(:name, [:name])
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
    |> Repo.insert!(insert_opts())
    |> then(fn dev_alias -> struct(dev_alias, seen_at: dev_alias.updated_at, nature: nature) end)
  end

  def delete(name_or_id) do
    with %Schema{} = a <- find(name_or_id) |> load_command_ids() |> load_datapoint_ids(),
         {:ok, cmd_count} <- Command.purge(a, :all),
         {:ok, dp_count} <- Datapoint.purge(a, :all),
         {:ok, %Schema{name: n}} <- Repo.delete(a) do
      res = [name: n, commands: cmd_count, datapoints: dp_count] |> Enum.reject(fn x -> x == 0 end)

      {:ok, res}
    else
      nil -> {:unknown, name_or_id}
      error -> error
    end
  end

  def exists?(name_or_id) do
    case find(name_or_id) do
      %Schema{} -> true
      _anything -> false
    end
  end

  @doc false
  @impl true
  def execute_cmd(%Alfred.Status{} = status, opts), do: Alfred.Status.raw(status) |> execute_cmd(opts)

  def execute_cmd(%Sally.DevAlias{} = dev_alias, opts) do
    new_cmd = Sally.Command.add(dev_alias, opts)

    rc = if(new_cmd.acked, do: :ok, else: :busy)

    preloads = [dev_alias: [device: [:host]]]
    Sally.Repo.preload(new_cmd, preloads) |> Sally.Command.Payload.send_cmd(opts)

    {rc, new_cmd}
  end

  def find(id) when is_integer(id), do: Sally.Repo.get_by(__MODULE__, id: id)
  def find(<<_::binary>> = name), do: Sally.Repo.get_by(__MODULE__, name: name)

  @dont_replace [:id, :last_seen_at, :updated_at]
  @replace Enum.reject(@columns, fn x -> x in @dont_replace end)
  @insert_opts [on_conflict: {:replace, @replace}, conflict_target: [:name]] ++ @returned
  def insert_opts, do: @insert_opts

  def load_aliases(%Sally.Device{id: id}) do
    load_alias_query(:device_id, id)
    |> Sally.Repo.all()
    |> nature_to_atom()
  end

  @fragment "case when ? then 'cmds' else 'datapoints' end"
  def load_alias_query(field, val) when is_atom(field) do
    Ecto.Query.from(dev_alias in Schema,
      where: field(dev_alias, ^field) == ^val,
      order_by: [asc: dev_alias.pio],
      # NOTE: join on device to get mutable
      join: device in Sally.Device,
      on: dev_alias.device_id == device.id,
      # NOTE: select merge the nature
      select_merge: %{nature: fragment(@fragment, device.mutable), seen_at: dev_alias.updated_at}
    )
  end

  def load_command_ids(schema_or_nil) do
    q = Ecto.Query.from(c in Command, select: [:id])
    Repo.preload(schema_or_nil, [cmds: q], force: true)
  end

  def load_datapoint_ids(schema_or_nil) do
    q = Ecto.Query.from(dp in Datapoint, select: [:id])
    Repo.preload(schema_or_nil, [datapoints: q], force: true)
  end

  def names do
    Ecto.Query.from(x in Schema, select: x.name, order_by: x.name) |> Repo.all()
  end

  def names_begin_with(pattern) when is_binary(pattern) do
    like_string = "#{pattern}%"

    Ecto.Query.from(x in Schema, where: like(x.name, ^like_string), order_by: x.name, select: x.name)
    |> Repo.all()
  end

  # NOTE: accepts a list, single dev alias or nil
  def nature_to_atom(dev_alias) do
    case dev_alias do
      %{nature: <<_::binary>> = x} -> struct(dev_alias, nature: String.to_atom(x))
      many when is_list(many) -> Enum.map(many, &nature_to_atom(&1))
      _ -> dev_alias
    end
  end

  def rename(opts) when is_list(opts) do
    with {:opts, from} when is_binary(from) <- {:opts, opts[:from]},
         {:opts, to} when is_binary(to) <- {:opts, opts[:to]},
         {:found, %Schema{} = x} <- {:found, find(from)},
         cs <- changeset(%{name: to}, x, [:name]),
         {:ok, %Schema{} = updated_schema} <- Repo.update(cs, returning: true) do
      updated_schema
    else
      {:opts, _} -> {:bad_args, opts}
      {:found, nil} -> {:not_found, opts[:from]}
      {:error, %Changeset{} = cs} -> {:name_taken, cs.changes.name}
    end
  end

  @impl true
  def status_lookup(%{name: name, nature: nature}, opts) do
    case nature do
      # :cmds -> find(name) |> Sally.Command.status(opts)
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

  def summary(%Schema{} = x), do: Map.take(x, [:name, :pio, :description, :ttl_ms])

  def ttl_reset(%Sally.Command{dev_alias_id: id, acked_at: ttl_at}) do
    load_alias_query(:id, id) |> Sally.Repo.one() |> nature_to_atom() |> ttl_reset(ttl_at)
  end

  def ttl_reset(%Sally.DevAlias{nature: nature} = dev_alias, ttl_at) do
    changeset(%{updated_at: ttl_at}, dev_alias, required: [:updated_at])
    |> Sally.Repo.update!(@returned)
    |> struct(nature: nature, seen_at: dev_alias.updated_at)
  end
end
