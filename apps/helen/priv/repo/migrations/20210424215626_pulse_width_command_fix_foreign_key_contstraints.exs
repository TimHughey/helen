defmodule Repo.Migrations.PulseWidthCommandFixForeignKeyContstraints do
  use Ecto.Migration

  def change do
    drop_if_exists(index(:pwm_cmd, [:alias_id]))

    alter table(:pwm_cmd) do
      remove(:alias_id, :bigint, from: references(:pwm_alias))

      add(
        :alias_id,
        references(:pwm_alias,
          on_update: :nilify_all,
          on_delete: :delete_all
        )
      )
    end

    create_if_not_exists(index(:pwm_cmd, [:alias_id]))
  end
end
