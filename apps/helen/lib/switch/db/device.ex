defmodule Switch.DB.Device do
  @moduledoc """
  Database implementation of Switch devices
  """

  require Logger
  use Timex

  use Ecto.Schema
  require Ecto.Query
  alias Ecto.Query

  alias Switch.DB.Alias, as: Alias
  alias Switch.DB.Device, as: Schema

  schema "switch_device" do
    field(:device, :string)
    field(:host, :string)
    field(:pio_count, :integer)
    field(:dev_latency_us, :integer, default: 0)
    field(:last_seen_at, :utc_datetime_usec)

    has_many(:aliases, Alias, references: :id, foreign_key: :device_id)

    timestamps(type: :utc_datetime_usec)
  end

  def aliases(%Schema{} = d) do
    load_aliases(d).aliases
  end

  # (1 of 2) convert parms into a map
  def changeset(%Schema{} = d, p) when is_list(p), do: changeset(d, Enum.into(p, %{}))

  # (2 of 2) params are a map
  def changeset(%Schema{} = d, p) when is_map(p) do
    alias Common.DB
    alias Ecto.Changeset

    d
    |> Changeset.cast(p, columns(:cast))
    |> Changeset.validate_required(columns(:required))
    |> Changeset.validate_format(:device, DB.name_regex())
    |> Changeset.validate_format(:host, DB.name_regex())
    |> Changeset.validate_number(:dev_latency_us, greater_than_or_equal_to: 0)
  end

  def columns(:all) do
    these_cols = [:__meta__, __schema__(:associations), __schema__(:primary_key)] |> List.flatten()

    %Schema{} |> Map.from_struct() |> Map.drop(these_cols) |> Map.keys() |> List.flatten()
  end

  def columns(:cast), do: columns(:all)
  def columns(:required), do: columns_all(drop: [:inserted_at, :updated_at])
  def columns(:replace), do: columns_all(drop: [:device, :inserted_at])

  def columns_all(opts) when is_list(opts) do
    keep_set = MapSet.new(opts[:only] || columns(:all))
    drop_set = MapSet.new(opts[:drop] || columns(:all))

    MapSet.difference(keep_set, drop_set) |> MapSet.to_list()
  end

  def devices_begin_with(pattern) when is_binary(pattern) do
    like_string = IO.iodata_to_binary([pattern, "%"])

    Query.from(x in Schema,
      where: like(x.device, ^like_string),
      order_by: x.device,
      select: x.device
    )
    |> Repo.all()
  end

  # (1 of 2) find with proper opts
  def find(opts) when is_list(opts) and opts != [] do
    case Repo.get_by(Schema, opts) do
      %Schema{} = x -> preload(x)
      x when is_nil(x) -> nil
    end
  end

  # (2 of 2) validate param and build opts for find/2
  def find(id_or_device) do
    case id_or_device do
      x when is_binary(x) -> find(device: x)
      x when is_integer(x) -> find(id: x)
      x -> {:bad_args, "must be binary or integer: #{inspect(x)}"}
    end
  end

  def find_alias(%Schema{aliases: aliases}, pio) when is_integer(pio) and pio >= 0 do
    Enum.find(aliases, nil, fn dev_alias -> Alias.for_pio?(dev_alias, pio) end)
  end

  # (1 of 2) load aliases for a schema
  def load_aliases(%Schema{} = d) do
    if Ecto.assoc_loaded?(d.aliases), do: d, else: Repo.preload(d, [:aliases])
  end

  # (2 of 2) handle use in a pipeline
  def load_aliases({rc, schema_or_error}) do
    case {rc, schema_or_error} do
      {:ok, %Schema{} = d} -> {:ok, load_aliases(d)}
      {rc, x} -> {rc, x}
    end
  end

  def pio_aliased?(%Schema{id: id, pio_count: pio_count}, pio) when pio < pio_count do
    d = Repo.get_by(Schema, id: id)

    case Repo.preload(d, aliases: Query.from(a in Alias, where: a.pio == ^pio)) do
      %Schema{aliases: []} -> false
      %Schema{aliases: x} when is_list(x) -> true
    end
  end

  def pio_count(%Schema{pio_count: pio_count}), do: pio_count

  def preload(%Schema{} = x), do: Repo.preload(x, [:aliases])

  # (1 of 2) receive the inbound msg, grab the keys of interest
  def upsert(%{device: _, host: _} = msg) do
    want = [:device, :host, :pio_count, :dev_latency_us, :last_seen_at]

    p = Map.take(msg, want) |> put_in([:last_seen_at], Timex.now())

    put_in(msg, [:device], upsert(%Schema{}, p)) |> Map.drop([:dev_latency_us, :pio_count])
  end

  # (2 of 2) perform the actual insert with conflict check (upsert)
  def upsert(%Schema{} = d, p) when is_map(p) do
    # assemble the opts for upsert
    # check for conflicts on :device
    # if there is a conflict only replace specified columns
    opts = [on_conflict: {:replace, columns(:replace)}, returning: true, conflict_target: [:device]]

    changeset(d, p) |> Repo.insert(opts) |> load_aliases()
  end
end
