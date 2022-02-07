defmodule Sally.Repo.Migrations.AddDatapointDevAliasIdIndex do
  use Ecto.Migration

  def change do
    drop_if_exists(index(:datapoint, [:dev_alias_id]))
    create(index(:datapoint, [:dev_alias_id]))
  end
end
