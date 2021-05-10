defmodule Repo.Migrations.SwitchCommandDropOldIndex do
  use Ecto.Migration

  def change do
    drop_if_exists(index(:switch_command, [:sent_at]))
  end
end
