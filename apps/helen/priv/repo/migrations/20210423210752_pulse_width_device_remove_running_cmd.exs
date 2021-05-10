defmodule Repo.Migrations.PulseWidthDeviceRemoveRunningCmd do
  use Ecto.Migration

  def change do
    alter table(:pwm_device) do
      remove(:running_cmd, :utc_datetime_usec)
    end
  end
end
