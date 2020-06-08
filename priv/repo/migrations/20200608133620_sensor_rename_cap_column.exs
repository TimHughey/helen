defmodule Repo.Migrations.SensorRenameCapColumn do
  use Ecto.Migration

  def change do
    rename(table("sensor_datapoint"), :moisture, to: :capacitance)
  end
end
