defmodule Repo.Migrations.SwitchCommandCorrectForeignKeyConstraints do
  use Ecto.Migration

  def change do
    drop_if_exists(index(:switch_command, [:alias_id]))

    alter table(:switch_command) do
      remove(:alias_id, :bigint, from: references(:switch_alias))

      add(
        :alias_id,
        references(:switch_alias,
          on_update: :nilify_all,
          on_delete: :delete_all
        )
      )
    end

    create_if_not_exists(index(:switch_command, [:alias_id]))
  end
end
