defmodule Sally.Repo.Migrations.HostRenameAtColumns do
  use Ecto.Migration

  def change do
    rename(table("host"), :last_start_at, to: :start_at)
    rename(table("host"), :last_seen_at, to: :seen_at)
  end
end
