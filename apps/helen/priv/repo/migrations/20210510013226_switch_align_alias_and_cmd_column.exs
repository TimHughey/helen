defmodule Repo.Migrations.SwitchAlignAliasAndCmdColumn do
  use Ecto.Migration

  def change do
    rename(table(:switch_alias), :remote_cmd, to: :cmd)
  end
end
