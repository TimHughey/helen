defmodule Repo.Migrations.DropDiscoveredAt do
  use Ecto.Migration

  def change do
    alter table("switch_device") do
      remove(:discovered_at, :utc_datetime_usec)
    end

    alter table("pwm_device") do
      remove(:discovered_at, :utc_datetime_usec)
    end

    alter table("sensor_device") do
      remove(:discovered_at, :utc_datetime_usec)
    end
  end
end
