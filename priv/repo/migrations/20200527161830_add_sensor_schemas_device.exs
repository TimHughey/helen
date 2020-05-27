defmodule Repo.Migrations.AddSensorSchemasDevice do
  use Ecto.Migration

  def change do
    create(table("sensor_device")) do
      add(:device, :string, null: false)
      add(:host, :string, null: false)
      add(:dev_latency_us, :integer, null: false, default: 0)
      add(:last_seen_at, :utc_datetime_usec)
      add(:discovered_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      index("sensor_device", [:device],
        name: "sensor_device_unique_index",
        unique: true
      )
    )
  end
end
