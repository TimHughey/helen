defmodule Sally.Repo.Migrations.AddDatapointDevAliasIdReadingAtIndex do
  use Ecto.Migration

  def change do
    drop_if_exists(index(:datapoint, [:dev_alias_id, :reading_at]))
    create(index(:datapoint, [:dev_alias_id, :reading_at]))
  end
end
