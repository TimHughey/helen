defmodule Repo.Migrations.SwitchDeviceAddPioCount do
  use Ecto.Migration

  def change do
    alter table(:switch_device) do
      add(:pio_count, :integer, null: false, default: 8)
    end
  end
end
