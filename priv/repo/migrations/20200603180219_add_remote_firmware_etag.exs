defmodule Repo.Migrations.AddRemoteFirmwareETAG do
  use Ecto.Migration

  def change do
    alter table("remote") do
      add(:firmware_etag, :string, size: 24, null: false, default: "<none>")
    end
  end
end
