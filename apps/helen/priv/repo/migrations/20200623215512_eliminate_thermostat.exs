defmodule Repo.Migrations.EliminateThermostat do
  use Ecto.Migration

  def change do
    drop_if_exists(table("thermostat_profile"))
    drop_if_exists(table("thermostat"))
  end
end
