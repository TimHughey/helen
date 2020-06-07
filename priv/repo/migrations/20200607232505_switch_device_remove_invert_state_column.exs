defmodule Repo.Migrations.SwitchDeviceRemoveInvertStateColumn do
  use Ecto.Migration

  def change do
    alter table("switch_alias") do
      remove(:invert_state)
    end
  end
end
