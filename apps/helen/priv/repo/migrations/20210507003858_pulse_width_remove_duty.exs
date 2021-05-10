defmodule Repo.Migrations.PulseWidthRemoveDuty do
  use Ecto.Migration

  def change do
    alter table(:pwm_alias) do
      remove(:duty)
      remove(:duty_min)
      remove(:duty_max)
    end
  end
end
