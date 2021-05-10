defmodule Repo.Migrations.CleanUpSwitchAndPwmIndexes do
  use Ecto.Migration

  def change do
    drop_if_exists(index(:switch_alias, :name, name: "switch_alias_name_hash_index"))
    drop_if_exists(index(:switch_device, :device, name: "switch_device_device_hash_index"))
    drop_if_exists(index(:switch_device, :device, name: "switch_device_device_index"))

    create_if_not_exists(index(:switch_device, :device, name: "switch_device_unique_index", unique: true))
  end
end
