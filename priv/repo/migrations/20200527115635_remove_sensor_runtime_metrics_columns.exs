defmodule Repo.Migrations.RemoveSensorRuntimeMetricsColumns do
  use Ecto.Migration

  def change do
    alter table("sensor") do
      # removing embedded runtime_metrics (for now)

      remove(:runtime_metrics, :map,
        null: false,
        default: %{external_update: false, cmd_rt: true}
      )
    end
  end
end
