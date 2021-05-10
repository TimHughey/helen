defmodule Repo.Migrations.CorrectSwitchCmdReferencesToSwitchAlias do
  use Ecto.Migration

  def change do
    drop(constraint(:switch_cmd, "switch_cmd_alias_id_fkey"))

    alter table(:switch_cmd) do
      modify(:alias_id, references(:switch_alias, on_delete: :nilify_all, on_update: :update_all))
    end
  end
end
