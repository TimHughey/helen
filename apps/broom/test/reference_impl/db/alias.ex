defmodule Broom.DB.Alias do
  @moduledoc false
  use Ecto.Schema

  alias Ecto.Query
  require Query

  alias __MODULE__, as: Schema
  alias Broom.DB.{Command, Device}
  alias BroomRepo, as: Repo

  @pio_min 0
  @ttl_default 2000
  @ttl_min 50

  schema "broom_alias" do
    field(:name, :string)
    field(:cmd, :string, default: "unknown")
    field(:description, :string, default: "<none>")
    field(:pio, :integer)
    field(:ttl_ms, :integer, default: @ttl_default)

    belongs_to(:device, Device)

    has_many(:cmds, Command,
      references: :id,
      foreign_key: :alias_id,
      preload_order: [desc: :inserted_at]
    )

    timestamps(type: :utc_datetime_usec)
  end

  def create(%Device{id: id}, name, pio, opts \\ []) when is_binary(name) and is_list(opts) do
    %{
      device_id: id,
      name: name,
      pio: pio,
      description: opts[:description] || "<none>",
      ttl_ms: opts[:ttl_ms] || @ttl_default
    }
    |> upsert()
  end

  def update_cmd(alias_id, cmd) do
    schema = Repo.get!(Schema, alias_id)

    %{cmd: cmd}
    |> changeset(schema)
    |> Repo.update!()
  end

  defp changeset(changes, %Schema{} = a) do
    alias Ecto.Changeset

    a
    |> Changeset.cast(changes, columns(:cast))
    |> Changeset.validate_required(columns(:required))
    |> Changeset.validate_length(:name, min: 3, max: 32)
    |> Changeset.validate_length(:description, max: 50)
    |> Changeset.validate_length(:cmd, max: 32)
    |> Changeset.validate_number(:pio, greater_than_or_equal_to: @pio_min)
    |> Changeset.validate_number(:ttl_ms, greater_than_or_equal_to: @ttl_min)
    |> Changeset.unique_constraint(:name, [:name])
  end

  # helpers for changeset columns
  defp columns(:all) do
    these_cols = [:__meta__, __schema__(:associations), __schema__(:primary_key)] |> List.flatten()

    %Schema{} |> Map.from_struct() |> Map.drop(these_cols) |> Map.keys() |> List.flatten()
  end

  defp columns(:cast), do: columns(:all)
  defp columns(:required), do: columns_all(only: [:device_id, :name, :pio])
  defp columns(:replace), do: columns_all(drop: [:name, :inserted_at])

  defp columns_all(opts) when is_list(opts) do
    keep_set = MapSet.new(opts[:only] || columns(:all))
    drop_set = MapSet.new(opts[:drop] || columns(:all))

    MapSet.difference(keep_set, drop_set) |> MapSet.to_list()
  end

  defp upsert(params) when is_map(params) do
    insert_opts = [on_conflict: {:replace, columns(:replace)}, returning: true, conflict_target: [:name]]

    params
    |> changeset(%Schema{})
    |> Repo.insert(insert_opts)
  end
end
