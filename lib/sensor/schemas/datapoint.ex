defmodule Sensor.Schemas.DataPoint do
  @moduledoc """
  Definition and database functions for Sensor.Schemas.DataPoint
  """

  require Logger
  use Timex
  use Ecto.Schema

  alias Sensor.Schemas.DataPoint
  alias Sensor.Schemas.Device

  schema "sensor_datapoint" do
    field(:temp_f, :float)
    field(:temp_c, :float)
    field(:relhum, :float)
    field(:moisture, :float)
    field(:reading_at, :utc_datetime_usec)

    belongs_to(:device, Device)

    # timestamps(type: :utc_datetime_usec)
  end

  def changeset(x, %{device: device} = p) when is_map(p) do
    import Ecto.Changeset,
      only: [
        cast: 3,
        put_assoc: 3,
        validate_required: 2
      ]

    cast(x, p, keys(:cast))
    |> put_assoc(:device, device)
    |> validate_required(keys(:required))
  end

  def keys(:all),
    do:
      Map.from_struct(%DataPoint{})
      |> Map.drop([:__meta__])
      |> Map.keys()
      |> List.flatten()

  def keys(:cast), do: keys_refine(:all, [:id, :device])
  def keys(:cast_assoc), do: [:device]

  # defp keys(:upsert), do: keys_refine(:all, [:id, :device])
  def keys(:required), do: [:device, :reading_at]

  defp keys_refine(base_keys, drop),
    do:
      MapSet.difference(MapSet.new(keys(base_keys)), MapSet.new(drop))
      |> MapSet.to_list()
end
