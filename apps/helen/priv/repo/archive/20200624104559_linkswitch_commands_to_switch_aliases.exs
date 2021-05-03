defmodule Repo.Migrations.LinkswitchCommandsToSwitchAliases do
  use Ecto.Migration

  def change do
    alter table("switch_command") do
      add(:alias_id, references("switch_alias"),
        on_delete: :nilify_all,
        on_update: :update_all
      )
    end
  end
end
