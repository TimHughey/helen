defmodule Sally.Repo.Migrations.AddCommandDevAliasIdIndex do
  use Ecto.Migration

  def change do
    drop_if_exists(index(:command, [:dev_alias_id]))
    create(index(:command, [:dev_alias_id]))
  end
end
