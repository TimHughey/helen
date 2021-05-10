defmodule Repo.Migrations.SwitchCommandAddCommandField do
  use Ecto.Migration

  @cmd_field_size 32

  def change do
    alter table(:switch_command) do
      add(:cmd, :string, size: @cmd_field_size)
    end
  end
end
