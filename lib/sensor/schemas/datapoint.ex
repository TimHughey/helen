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

  @doc """
  Returns the average of a specific field (column) from a list of %DataPoints{}
  """

  @doc since: "0.9.19"
  def avg_of(datapoints, column)
      when is_list(datapoints) and
             column in [:temp_f, :temp_c, :relhum, :moisture] do
    vals =
      Enum.into(datapoints, [], fn
        %DataPoint{} = dp -> Map.get(dp, column)
        _x -> nil
      end)

    with count when count > 0 <- Enum.count(vals),
         true <- Enum.all?(vals, &is_number/1) do
      Float.round(Enum.sum(vals) / count, 3)
    else
      _anything -> nil
    end
  end

  @doc since: "0.0.16"
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

  @doc since: "0.0.16"
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
