defmodule Repo.Migrations.CorrectSwitchCmdReferencesToSwitchAliasTakeTwo do
  use Ecto.Migration

  def change do
    drop(constraint(:switch_cmd, "switch_cmd_alias_id_fkey"))

    alter table(:switch_cmd) do
      modify(:alias_id, references(:switch_alias, on_delete: :delete_all, on_update: :update_all))
    end

    drop(constraint(:pwm_cmd, "pwm_cmd_alias_id_fkey"))

    alter table(:pwm_cmd) do
      modify(:alias_id, references(:pwm_alias, on_delete: :delete_all, on_update: :update_all))
    end
  end
end
