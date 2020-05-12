defmodule Repo.Migrations.CreateDefaultRemoteProfile do
  use Ecto.Migration

  def change do
    RemoteProfile.Schema.create("default")
  end
end
