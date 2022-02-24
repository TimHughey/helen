defmodule Sally.Repo.Migrations.DeviceMutableIndex do
  use Ecto.Migration

  def change do
    create(index(:device, [:mutable], unique: false))
  end
end
