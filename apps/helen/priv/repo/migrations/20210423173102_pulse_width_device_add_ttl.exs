defmodule Repo.Migrations.PulseWidthDeviceAddTTL do
  use Ecto.Migration

  def change do
    alter table("pwm_device") do
      add(:ttl_ms, :integer, null: false, default: 60_000)
    end
  end
end
