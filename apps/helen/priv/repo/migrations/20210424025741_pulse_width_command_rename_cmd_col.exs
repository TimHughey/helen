defmodule Repo.Migrations.PulseWidthCommandRenameCmdCol do
  use Ecto.Migration

  def change do
    rename(table(:pwm_cmd), :requested_cmd, to: :cmd)
  end
end
