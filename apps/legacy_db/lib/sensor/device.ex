defmodule LegacyDb.Sensor.Device do
  @moduledoc """
  Database functionality for Sensor Device
  """

  use Ecto.Schema

  alias LegacyDb.Sensor.Alias, as: Alias
  alias LegacyDb.Sensor.DataPoint, as: DataPoint
  # alias LegacyDb.Sensor.Device, as: Schema

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
end
