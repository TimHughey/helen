defmodule Repo.Migrations.AddSensorDeviceLastSeenAtIndex do
  use Ecto.Migration

  def change do
    create(
      index("sensor_device", [:last_seen_at],
        name: "sensor_device_last_seen_at_index"
      )
    )
  end
end
