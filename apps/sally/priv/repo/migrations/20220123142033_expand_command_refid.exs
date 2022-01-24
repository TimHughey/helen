defmodule Sally.Repo.Migrations.ExpandCommandRefid do
  use Ecto.Migration

  def change do
    alter table("command") do
      modify(:refid, :string, size: 48)
    end
  end
end
