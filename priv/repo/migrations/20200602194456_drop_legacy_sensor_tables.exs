defmodule Repo.Migrations.DropLegacySensorTables do
  use Ecto.Migration

  def change do
    drop(table("sensor_temperature"))
    drop(table("sensor_soil"))
    drop(table("sensor_relhum"))
    drop(table("sensor"))
  end
end
