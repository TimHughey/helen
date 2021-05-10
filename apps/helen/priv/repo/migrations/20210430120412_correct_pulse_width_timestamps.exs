defmodule Repo.Migrations.CorrectPulseWidthTimestamps do
  use Ecto.Migration

  def change do
    alter table(:pwm_device) do
      modify(:updated_at, :utc_datetime_usec)
      modify(:inserted_at, :utc_datetime_usec)
    end
  end
end
