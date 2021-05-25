defmodule Broom.DB.Device do
  @moduledoc false

  use Ecto.Schema

  alias __MODULE__, as: Schema
  alias Broom.DB.Alias

  schema "broom_device" do
    field(:device, :string)
    field(:host, :string)
    field(:pio_count, :integer)
    field(:dev_latency_us, :integer, default: 0)
    field(:last_seen_at, :utc_datetime_usec)

    has_many(:aliases, Alias, foreign_key: :device_id)

    timestamps(type: :utc_datetime_usec)
  end

  # NOTE: the reference implementation does not contain a function to create a device
  # See BroomTest.create_device/1

  def changeset(%Schema{} = d, p) when is_map(p) do
    alias Ecto.Changeset

    d
    |> Changeset.cast(p, columns(:cast))
    |> Changeset.validate_required(columns(:required))
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

  def load_aliases(tuple_or_schema) do
    case tuple_or_schema do
      {:ok, %Schema{} = d} -> {:ok, BroomRepo.preload(d, [:aliases])}
      %Schema{} = d -> BroomRepo.preload(d, [:aliases])
    end
  end

  def upsert(p) when is_map(p) do
    # assemble the opts for upsert
    # check for conflicts on :device
    # if there is a conflict only replace specified columns
    opts = [
      on_conflict: {:replace, columns(:replace)},
      returning: true,
      conflict_target: [:device]
    ]

    changeset(%Schema{}, p) |> BroomRepo.insert(opts) |> load_aliases()
  end
end
