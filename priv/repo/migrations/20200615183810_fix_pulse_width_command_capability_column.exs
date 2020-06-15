defmodule Repo.Migrations.FixPulseWidthCommandCapabilityColumn do
  use Ecto.Migration

  def change do
    rename(table("pwm_alias"), :type, to: :capability)
  end
end
