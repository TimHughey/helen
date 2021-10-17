defmodule LegacyDb.Sensor.Alias do
  @moduledoc """
  Database functionality for Sensor Alias
  """

  use Ecto.Schema

  # alias LegacyDb.Sensor.Alias, as: Schema
  alias LegacyDb.Sensor.Device

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
end
