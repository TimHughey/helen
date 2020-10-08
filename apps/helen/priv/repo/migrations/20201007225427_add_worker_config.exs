defmodule Repo.Migrations.AddWorkerConfig do
  @moduledoc false

  use Ecto.Migration

  def change do
    drop_if_exists(index(:worker_config_line, [:worker_config_id]))
    drop_if_exists(table(:worker_config_line))

    drop_if_exists(index(:worker_config, [:worker_name, :version]))
    drop_if_exists(table(:worker_config))

    create(table(:worker_config)) do
      add(:module, :string, size: 60, null: false)
      add(:comment, :string, size: 80, default: "<none>")
      add(:version, :string, size: 12, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:worker_config, [:module, :version], unique: true))

    create(table("worker_config_line")) do
      add(:line, :text, null: false)

      add(
        :worker_config_id,
        references(:worker_config,
          on_delete: :delete_all,
          on_update: :update_all
        )
      )
    end

    create(index(:worker_config_line, [:worker_config_id]))
  end
end
