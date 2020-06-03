defmodule Sensor.Schemas.Device do
  @moduledoc """
  Definition and database functions for Sensor.Schemes.Device
  """

  use Ecto.Schema

  alias Sensor.Schemas.{Alias, DataPoint, Device}

  schema "sensor_device" do
    field(:device, :string)
    field(:host, :string)
    field(:dev_latency_us, :integer, default: 0)
    field(:last_seen_at, :utc_datetime_usec)
    field(:discovered_at, :utc_datetime_usec)

    has_many(:datapoints, DataPoint)

    has_one(:_alias_, Alias, references: :id, foreign_key: :device_id)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(x, p) when is_map(p) or is_list(p) do
    import Ecto.Changeset,
      only: [
        cast: 3,
        validate_required: 2,
        validate_format: 3,
        validate_number: 3
      ]

    import Common.DB, only: [name_regex: 0]

    cast(x, Enum.into(p, %{}), keys(:cast))
    |> validate_required(keys(:required))
    |> validate_format(:device, name_regex())
    |> validate_format(:host, name_regex())
    |> validate_number(:dev_latency_us, greater_than_or_equal_to: 0)
  end

  def keys(:all),
    do:
      Map.from_struct(%Device{})
      |> Map.drop([:__meta__, :_alias_, :id, :datapoints])
      |> Map.keys()
      |> List.flatten()

  def keys(:cast), do: keys(:all)

  # defp keys(:upsert), do: keys_drop(:all, [:id, :device])

  def keys(:replace),
    do:
      keys_drop(:all, [
        :device,
        :discovered_at,
        :inserted_at
      ])

  def keys(:required),
    do: keys_drop(:cast, [:updated_at, :inserted_at])

  defp keys_drop(base_keys, drop),
    do:
      MapSet.difference(MapSet.new(keys(base_keys)), MapSet.new(drop))
      |> MapSet.to_list()
end
