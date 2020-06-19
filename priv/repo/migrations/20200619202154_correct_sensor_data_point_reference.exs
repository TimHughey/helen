defmodule Repo.Migrations.CorrectSensorDataPointReference do
  use Ecto.Migration

  def change do
    alter table("sensor_datapoint") do
      remove(:device_id, :bigint,
        from:
          references("sensor_device",
            on_update: :update_all,
            on_delete: :delete_all
          )
      )

      add(
        :device_id,
        references("sensor_device",
          on_update: :update_all,
          on_delete: :delete_all
        )
      )
    end
  end
end
