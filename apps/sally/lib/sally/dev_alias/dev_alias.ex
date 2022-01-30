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
  use Alfred.Status
  use Alfred.Execute, broom: Sally.Command
  use Alfred.JustSaw

  alias __MODULE__, as: Schema
  alias Ecto.Changeset
  alias Sally.{Command, Datapoint, Device, Repo}

  @pio_min 0
  @ttl_default 15_000
  @ttl_min 50

  @type list_or_schema() :: [Ecto.Schema.t(), ...] | Ecto.Schema.t()

  schema "dev_alias" do
    field(:name, :string)
    field(:pio, :integer)
    field(:description, :string, default: "<none>")
    field(:ttl_ms, :integer, default: @ttl_default)

    belongs_to(:device, Device)
    has_many(:cmds, Command, foreign_key: :dev_alias_id, preload_order: [desc: :sent_at])
    has_many(:datapoints, Datapoint, foreign_key: :dev_alias_id, preload_order: [desc: :reading_at])

    field(:status, :map, virtual: true, default: %{})

    timestamps(type: :utc_datetime_usec)
  end

  @returned [returning: true]

  def align_status(%Sally.DevAlias{pio: pio} = dev_alias, dispatch) do
    %{data: %{pins: pin_data}, recv_at: align_at} = dispatch
    pin_cmd = Sally.Command.pin_cmd(pio, pin_data)

    # latest_cmd = Sally.Command.saved(dev_alias)

    latest_cmd = Sally.Command.latest(dev_alias, :id)

    case latest_cmd do
      %{acked: false, acked_at: nil} -> :busy
      %{acked: true, cmd: ^pin_cmd, orphaned: false} -> :aligned
      _ -> Sally.Command.align_cmd(dev_alias, pin_cmd, align_at)
    end
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

    %{
      name: opts[:name],
      pio: opts[:pio],
      description: opts[:description] || dev_alias.description,
      ttl_ms: opts[:ttl_ms] || dev_alias.ttl_ms
    }
    |> changeset(dev_alias)
    |> Repo.insert(insert_opts())
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
  def execute_cmd(%Alfred.Status{} = status, opts), do: Alfred.Status.raw(status) |> execute_cmd(opts)

  def execute_cmd(%Sally.DevAlias{} = dev_alias, opts) do
    new_cmd = Sally.Command.add(dev_alias, opts)

    rc = if(new_cmd.acked, do: :ok, else: :busy)

    preloads = [dev_alias: [device: [:host]]]
    Sally.Repo.preload(new_cmd, preloads) |> Sally.Command.Payload.send_cmd(opts)

    {rc, new_cmd}
  end

  # (1 of 2) find with proper opts
  def find(opts) when is_list(opts) and opts != [] do
    case Repo.get_by(Schema, opts) do
      %Schema{} = x -> load_device(x) |> load_cmd_last()
      x when is_nil(x) -> nil
    end
  end

  # (2 of 2) validate param and build opts for find/2
  def find(id_or_schema) do
    case id_or_schema do
      x when is_binary(x) -> find(name: x)
      x when is_integer(x) -> find(id: x)
      x -> {:bad_args, "must be binary or integer: #{inspect(x)}"}
    end
  end

  def find_by_name(name) when is_binary(name), do: find(name: name)

  @dont_replace [:id, :last_seen_at, :updated_at]
  @replace Enum.reject(@columns, fn x -> x in @dont_replace end)
  @insert_opts [on_conflict: {:replace, @replace}, conflict_target: [:name]] ++ @returned
  def insert_opts, do: @insert_opts

  # @doc """
  #   Mark a list of DevAlias as just seen within an Ecto.Multi sequence
  #
  #   Returns:
  #   ```
  #   {:ok, [%DevAlias{} | []]}  # success
  #   {:error, error}            # update failed for one DevAlias
  #   ```
  #
  # """
  # @doc since: "0.5.10"
  # @type multi_changes :: %{aliases: [Ecto.Schema.t(), ...]}
  # @type ok_tuple :: {:ok, Ecto.Schema.t()}
  # @type error_tuple :: {:error, any()}
  # @type db_result :: ok_tuple() | error_tuple()
  # @spec just_saw(Ecto.Repo.t(), multi_changes(), DateTime.t()) :: db_result()
  # def just_saw(repo, %{aliases: schemas}, %DateTime{} = seen_at) when is_list(schemas) do
  #   for %Schema{} = schema <- schemas, reduce: {:ok, []} do
  #     {:ok, acc} ->
  #       cs = changeset(%{updated_at: seen_at}, schema)
  #
  #       case repo.update(cs, returning: true) do
  #         {:ok, %Schema{} = x} -> {:ok, [x | acc]}
  #         {:error, error} -> {:error, error}
  #       end
  #
  #     {:error, _} = acc ->
  #       acc
  #   end
  # end

  def just_saw_db(%{} = multi_changes) do
    %{device: %{id: device_id}, dispatch: %{sent_at: seen_at}} = multi_changes

    Ecto.Query.from(dev_alias in Sally.DevAlias,
      update: [set: [updated_at: ^seen_at]],
      where: [device_id: ^device_id],
      select: [:id, :name, :ttl_ms, :updated_at]
    )
  end

  # @doc """
  #   Mark a single DevAlias (by id) as just seen
  #
  #   Looks up the DevAlias by id then reuses `just_saw/3`
  # """
  # @doc since: "0.5.10"
  # @spec just_saw_id(Ecto.Repo.t(), multi_changes, id :: integer, DateTime.t()) :: db_result()
  # def just_saw_id(repo, _changes, id, %DateTime{} = seen_at) when is_integer(id) do
  #   case repo.get(Schema, id) do
  #     %Schema{} = x -> just_saw(repo, %{aliases: [x]}, seen_at)
  #     x when is_nil(x) -> just_saw(repo, %{aliases: []}, seen_at)
  #   end
  # end

  def load_aliases(%Sally.Device{id: device_id}) do
    Ecto.Query.from(a in Schema, where: [device_id: ^device_id], order_by: [asc: a.pio])
    |> Sally.Repo.all()
  end

  # def load_aliases(repo, multi_changes) do
  #   %{device: %{id: device_id}} = multi_changes
  #
  #   Ecto.Query.from(a in Schema, where: [device_id: ^device_id], order_by: [asc: a.pio])
  #   |> then(fn query -> {:ok, repo.all(query)} end)
  # end

  def load_cmd_last(%Schema{} = x) do
    cmd_query = Command.query_preload_latest_cmd()
    Repo.preload(x, cmds: cmd_query)
  end

  def load_command_ids(schema_or_nil) do
    q = Ecto.Query.from(c in Command, select: [:id])
    Repo.preload(schema_or_nil, [cmds: q], force: true)
  end

  def load_datapoint_ids(schema_or_nil) do
    q = Ecto.Query.from(dp in Datapoint, select: [:id])
    Repo.preload(schema_or_nil, [datapoints: q], force: true)
  end

  def load_device(schema_or_tuple) do
    case schema_or_tuple do
      {:ok, %Schema{} = a} -> {:ok, Repo.preload(a, [:device])}
      %Schema{} = a -> Repo.preload(a, [:device])
      x -> x
    end
  end

  def load_info(%Schema{} = schema) do
    schema |> Repo.preload(device: [:host]) |> load_cmd_last()
  end

  def names do
    Ecto.Query.from(x in Schema, select: x.name, order_by: x.name) |> Repo.all()
  end

  def names_begin_with(pattern) when is_binary(pattern) do
    like_string = "#{pattern}%"

    Ecto.Query.from(x in Schema, where: like(x.name, ^like_string), order_by: x.name, select: x.name)
    |> Repo.all()
  end

  def preload_query do
    Ecto.Query.from(a in Schema, order_by: [asc: a.pio])
  end

  def rename(opts) when is_list(opts) do
    with {:opts, from} when is_binary(from) <- {:opts, opts[:from]},
         {:opts, to} when is_binary(to) <- {:opts, opts[:to]},
         {:found, %Schema{} = x} <- {:found, find_by_name(from)},
         cs <- changeset(%{name: to}, x, [:name]),
         {:ok, %Schema{} = updated_schema} <- Repo.update(cs, returning: true) do
      updated_schema
    else
      {:opts, _} -> {:bad_args, opts}
      {:found, nil} -> {:not_found, opts[:from]}
      {:error, %Changeset{} = cs} -> {:name_taken, cs.changes.name}
    end
  end

  def status_lookup(%{name: name, nature: nature}, opts) do
    case nature do
      :cmds -> find(name) |> Sally.Command.status(opts)
      :datapoints -> Sally.Datapoint.status(name, opts)
    end
    |> status_lookup_finalize()
  end

  @doc false
  def status_lookup_finalize(dev_alias) do
    case dev_alias do
      %{cmds: %Ecto.Association.NotLoaded{}} -> struct(dev_alias, cmds: [])
      %{datapoints: %Ecto.Association.NotLoaded{}} -> struct(dev_alias, datapoints: [])
      other -> other
    end
  end

  def summary(%Schema{} = x), do: Map.take(x, [:name, :pio, :description, :ttl_ms])

  def ttl_reset(%Sally.Command{dev_alias_id: id, acked_at: ttl_at}) do
    Sally.Repo.load(Schema, id: id) |> ttl_reset(ttl_at)
  end

  def ttl_reset(%Sally.DevAlias{} = dev_alias, ttl_at) do
    cs = changeset(%{updated_at: ttl_at}, dev_alias, required: [:updated_at])

    Sally.Repo.update!(cs, @returned)
  end
end
