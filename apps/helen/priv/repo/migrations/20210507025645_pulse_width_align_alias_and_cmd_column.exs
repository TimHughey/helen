defmodule Repo.Migrations.PulseWidthAlignAliasAndCmdColumn do
  use Ecto.Migration

  def change do
    rename(table(:pwm_alias), :remote_cmd, to: :cmd)
  end
end
