defmodule Repo.Migrations.SwitchRefactorToAlignWithPulseWidthAndSwitch do
  use Ecto.Migration

  def change do
    drop_if_exists(index(:sensor_datapoint, [:reading_at]))
    drop_if_exists(table(:sensor_datapoint))

    create table(:sensor_datapoint) do
      add(:temp_c, :float)
      add(:relhum, :float)
      add(:alias_id, references(:sensor_alias, on_delete: :delete_all, on_update: :update_all))
      add(:reading_at, :utc_datetime_usec, null: false)
    end

    create(index(:sensor_datapoint, [:alias_id]))
    create(index(:sensor_datapoint, [:reading_at], using: :brin))

    alter table(:sensor_alias) do
      remove(:type)
    end
  end
end
