defmodule Sally.Repo.Migrations.SallyDeviceRemoveLastSeenAt do
  use Ecto.Migration

  def change do
    alter table("device") do
      remove(:last_seen_at)
    end
  end
end
