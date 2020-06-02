defmodule Sensor.Schemas.Alias do
  @moduledoc """
  Defines the schema and database implementation for Sensor Aliases
  """

  use Ecto.Schema

  alias Sensor.Schemas.Alias
  alias Sensor.Schemas.Device

  schema "sensor_alias" do
    field(:name, :string)
    field(:device_id, :integer)
    field(:description, :string, default: "<none>")
    field(:type, :string, default: "auto")
    field(:ttl_ms, :integer, default: 60_000)

    belongs_to(:device, Device,
      source: :device_id,
      references: :id,
      foreign_key: :device_id,
      define_field: false
    )

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(x, p) when is_map(p) do
    import Ecto.Changeset,
      only: [
        cast: 3,
        validate_required: 2,
        validate_format: 3,
        validate_number: 3
      ]

    import Common.DB, only: [name_regex: 0]

    cast(x, p, keys(:cast))
    |> validate_required(keys(:required))
    |> validate_format(:name, name_regex())
    |> validate_number(:ttl_ms, greater_than_or_equal_to: 0)
  end

  def keys(:all),
    do:
      Map.from_struct(%Alias{})
      |> Map.drop([:__meta__, :id, :device])
      |> Map.keys()
      |> List.flatten()

  def keys(:cast), do: keys(:all)

  # defp keys(:upsert), do: keys_drop(:all, [:id, :device])

  def keys(:replace),
    do: keys_drop(:all, [:name, :inserted_at])

  def keys(:update),
    do: keys_drop(:all, [:inserted_at])

  def keys(:required),
    do:
      keys_drop(:cast, [
        :description,
        :type,
        :ttl_ms,
        :updated_at,
        :inserted_at
      ])

  defp keys_drop(base_keys, drop),
    do:
      MapSet.difference(MapSet.new(keys(base_keys)), MapSet.new(drop))
      |> MapSet.to_list()
end
