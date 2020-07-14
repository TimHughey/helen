defmodule Repo.Migrations.DropMessageSave do
  use Ecto.Migration

  def change do
    drop_if_exists(table(:message))
  end
end
