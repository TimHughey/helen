defmodule Repo.Migrations.SwitchAliasAddRemoteCmd do
  use Ecto.Migration

  def change do
    alter table(:switch_alias) do
      add(:remote_cmd, :string, size: @cmd_size, null: false, default: "unknown")
    end
  end
end
