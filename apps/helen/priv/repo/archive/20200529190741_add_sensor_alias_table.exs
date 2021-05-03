defmodule Repo.Migrations.AddSensorAliasTable do
  use Ecto.Migration

  def change do
    create(table("sensor_alias")) do
      add(:name, :string, null: false)

      add(
        :device_id,
        references("sensor_device",
          on_delete: :delete_all,
          on_update: :update_all
        )
      )

      add(:description, :string, size: 50, default: "<none>")
      add(:type, :string, size: 20, null: false, default: "auto")
      add(:ttl_ms, :integer, null: false, default: 60_000)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:sensor_alias, [:name], unique: true))
  end
end
