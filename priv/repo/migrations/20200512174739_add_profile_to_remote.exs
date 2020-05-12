defmodule Repo.Migrations.AddProfileToRemote do
  use Ecto.Migration

  def change do
    alter table("remote") do
      add(:profile, :string, null: false, default: "default")
    end
  end
end
