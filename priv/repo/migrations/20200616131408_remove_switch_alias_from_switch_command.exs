defmodule Repo.Migrations.RemoveSwitchAliasFromSwitchCommand do
  use Ecto.Migration

  def change do
    alter(table("switch_command")) do
      remove(:sw_alias, :string)
    end

    rename(table("pwm_cmd"), :pwm_id, to: :device_id)
  end
end
