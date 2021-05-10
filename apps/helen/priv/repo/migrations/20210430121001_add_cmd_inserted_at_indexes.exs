defmodule Repo.Migrations.AddCmdInsertedAtIndexes do
  use Ecto.Migration

  def change do
    for table <- [:switch_cmd, :pwm_cmd] do
      create_if_not_exists(index(table, [:inserted_at], using: "brin"))
    end
  end
end
