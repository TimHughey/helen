defmodule Sally.DevAlias do
  @moduledoc """
  Database implementation of Sally.PulseWidth Aliases
  """
  require Logger

  use Ecto.Schema
  require Ecto.Query

  alias __MODULE__, as: Schema
  alias Sally.{Command, Datapoint, Device, Repo}

  @pio_min 0
  @ttl_default 2000
  @ttl_min 50

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

  def changeset(changes, %Schema{} = a) do
    alias Ecto.Changeset

    a
    |> Changeset.cast(changes, columns(:cast))
    |> Changeset.validate_required(columns(:required))
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
      description: opts[:description] || "<none>",
      ttl_ms: opts[:ttl_ms] || @ttl_default
    }
    |> changeset(dev_alias)
    |> Repo.insert!(on_conflict: {:replace, columns(:replace)}, returning: true, conflict_target: [:name])
  end

  def delete(name_or_id) do
    with %Schema{} = a <- find(name_or_id) |> load_command_ids(),
         {:ok, count} <- Command.purge(a, :all),
         {:ok, %Schema{name: n}} <- Repo.delete(a) do
      {:ok, [name: n, commands: count]}
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

  def for_pio?(%Schema{pio: alias_pio}, pio), do: alias_pio == pio

  defp load_command_ids(schema_or_nil) do
    q = Ecto.Query.from(c in Command, select: [:id])
    Repo.preload(schema_or_nil, [cmds: q], force: true)
  end

  def load_device(schema_or_tuple) do
    case schema_or_tuple do
      {:ok, %Schema{} = a} -> {:ok, Repo.preload(a, [:device])}
      %Schema{} = a -> Repo.preload(a, [:device])
      x -> x
    end
  end

  def load_cmd_last(%Schema{} = x) do
    Repo.preload(x, cmds: Ecto.Query.from(d in Command, order_by: [desc: d.sent_at], limit: 1))
  end

  def names do
    Ecto.Query.from(x in Schema, select: x.name, order_by: x.name) |> Repo.all()
  end

  def names_begin_with(pattern) when is_binary(pattern) do
    like_string = "#{pattern}%"

    Ecto.Query.from(x in Schema, where: like(x.name, ^like_string), order_by: x.name, select: x.name)
    |> Repo.all()
  end
end
