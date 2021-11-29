defmodule Sally.DevAlias do
  @moduledoc """
  Database implementation of Sally.PulseWidth Aliases
  """
  require Logger

  use Ecto.Schema
  require Ecto.Query

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

    timestamps(type: :utc_datetime_usec)
  end

  def add_datapoint(repo, %{aliases: dev_aliases}, raw_data, %DateTime{} = reading_at)
      when is_map(raw_data) do
    for %Schema{} = schema <- dev_aliases, reduce: {:ok, []} do
      {:ok, acc} ->
        case Datapoint.add(repo, schema, raw_data, reading_at) do
          {:ok, %Datapoint{} = x} -> {:ok, [x] ++ acc}
          {:error, _reason} = rc -> rc
        end
    end
  end

  def changeset(changes, %Schema{} = a, opts \\ []) do
    required = opts[:required] || columns(:required)

    a
    |> Changeset.cast(changes, columns(:cast))
    |> Changeset.validate_required(required)
    |> Changeset.validate_format(:name, ~r/^[a-z~][\w .:-]+[[:alnum:]]$/i)
    |> Changeset.validate_length(:name, max: 128)
    |> Changeset.validate_number(:pio, greater_than_or_equal_to: @pio_min)
    |> Changeset.validate_length(:description, max: 128)
    |> Changeset.validate_number(:ttl_ms, greater_than_or_equal_to: @ttl_min)
    |> Changeset.unique_constraint(:name, [:name])
  end

  # helpers for changeset columns
  def columns(:all) do
    these_cols = [:__meta__, __schema__(:associations), __schema__(:primary_key)] |> List.flatten()

    %Schema{} |> Map.from_struct() |> Map.drop(these_cols) |> Map.keys() |> List.flatten()
  end

  def columns(:cast), do: columns(:all)
  def columns(:required), do: columns_all(only: [:device_id, :name, :pio])
  def columns(:replace), do: columns_all(drop: [:name, :inserted_at])

  def columns_all(opts) when is_list(opts) do
    keep_set = MapSet.new(opts[:only] || columns(:all))
    drop_set = MapSet.new(opts[:drop] || columns(:all))

    MapSet.difference(keep_set, drop_set) |> MapSet.to_list()
  end

  def create(%Device{} = device, opts) do
    dev_alias = Ecto.build_assoc(device, :aliases)

    %{
      name: opts[:name],
      pio: opts[:pio],
      description: opts[:description] || dev_alias.description,
      ttl_ms: opts[:ttl_ms] || dev_alias.ttl_ms
    }
    |> changeset(dev_alias)
    |> Repo.insert(on_conflict: {:replace, columns(:replace)}, returning: true, conflict_target: [:name])
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

  @doc """
  Get the `Sally.Device` id from a `DevAlias` or list of `DevAlias`
  """
  @spec device_id(list_or_schema) :: pos_integer()
  def device_id([%Schema{} = x | _]), do: device_id(x)
  def device_id(%Schema{device_id: x}), do: x

  def exists?(name_or_id) do
    case find(name_or_id) do
      %Schema{} -> true
      _anything -> false
    end
  end

  def explain(name, opts \\ [analyze: true]) do
    import Ecto.Query, only: [where: 2]

    %Schema{id: schema_id} = find(name)

    query = Command.query_preload_latest_cmd(schema_id)

    for line <- Repo.explain(:all, query, opts) |> String.split("\n") do
      IO.puts(line)
    end

    :ok
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

  def for_pio?(%Schema{pio: alias_pio}, pio), do: alias_pio == pio

  @doc """
    Mark a list of DevAlias as just seen within an Ecto.Multi sequence

    Returns:
    ```
    {:ok, [%DevAlias{} | []]}  # success
    {:error, error}            # update failed for one DevAlias
    ```

  """
  @doc since: "0.5.10"
  @type multi_changes :: %{aliases: [Ecto.Schema.t(), ...]}
  @type ok_tuple :: {:ok, Ecto.Schema.t()}
  @type error_tuple :: {:error, any()}
  @type db_result :: ok_tuple() | error_tuple()
  @spec just_saw(Ecto.Repo.t(), multi_changes(), DateTime.t()) :: db_result()
  def just_saw(repo, %{aliases: schemas}, %DateTime{} = seen_at) when is_list(schemas) do
    for %Schema{} = schema <- schemas, reduce: {:ok, []} do
      {:ok, acc} ->
        cs = changeset(%{updated_at: seen_at}, schema)

        case repo.update(cs, returning: true) do
          {:ok, %Schema{} = x} -> {:ok, [x] ++ acc}
          {:error, error} -> {:error, error}
        end

      {:error, _} = acc ->
        acc
    end
  end

  @doc """
    Mark a single DevAlias (by id) as just seen

    Looks up the DevAlias by id then reuses `just_saw/3`
  """
  @doc since: "0.5.10"
  @spec just_saw_id(Ecto.Repo.t(), multi_changes, id :: integer, DateTime.t()) :: db_result()
  def just_saw_id(repo, _changes, id, %DateTime{} = seen_at) when is_integer(id) do
    case repo.get(Schema, id) do
      %Schema{} = x -> just_saw(repo, %{aliases: [x]}, seen_at)
      x when is_nil(x) -> just_saw(repo, %{aliases: []}, seen_at)
    end
  end

  def load_aliases(repo, multi_changes) do
    q = Ecto.Query.from(a in Schema, where: a.device_id == ^multi_changes.device.id, order_by: [asc: a.pio])

    {:ok, q |> repo.all()}
  end

  def load_cmd_last(%Schema{} = x) do
    cmd_query = Command.query_preload_latest_cmd()
    Repo.preload(x, cmds: cmd_query)
  end

  def load_alias_with_last_cmd(name) when is_binary(name) do
    cmd_q = Command.query_preload_latest_cmd()

    Ecto.Query.from(a in Schema,
      where: a.name == ^name,
      order_by: [asc: a.pio],
      preload: [cmds: ^cmd_q, device: []]
    )
    |> Repo.one()
  end

  def load_aliases_with_last_cmd(repo, %{device: device} = _multi_changes) do
    import Ecto.Query, only: [from: 2]

    cmd_query = Command.query_preload_latest_cmd()

    all_query =
      from(a in Schema,
        where: [device_id: ^device.id],
        order_by: [asc: a.pio],
        preload: [cmds: ^cmd_query]
      )

    {:ok, all_query |> repo.all()}
  end

  defp load_command_ids(schema_or_nil) do
    q = Ecto.Query.from(c in Command, select: [:id])
    Repo.preload(schema_or_nil, [cmds: q], force: true)
  end

  defp load_datapoint_ids(schema_or_nil) do
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

  def summary(%Schema{} = x), do: Map.take(x, [:name, :pio, :description, :ttl_ms])
end
