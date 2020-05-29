defmodule Repo.Migrations.AddSensorDataPointTable do
  use Ecto.Migration

  def change do
    create(table("sensor_datapoint")) do
      add(:temp_f, :real)
      add(:temp_c, :real)
      add(:relhum, :real)
      add(:moisture, :real)
      add(:device_id, references(:sensor_device))
      add(:reading_at, :utc_datetime_usec)
    end

    create(index("sensor_datapoint", [:device_id]))
    create(index("sensor_datapoint", [:reading_at]))
  end
end
