defmodule Sally.Repo.Migrations.AddDevAliasDeviceIdIndex do
  use Ecto.Migration

  def change do
    create(index(:dev_alias, [:device_id]))
  end
end
