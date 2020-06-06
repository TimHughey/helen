defmodule Repo.Migrations.PulseWidthChangeSequenceColumnName do
  use Ecto.Migration

  def change do
    alter table("pwm") do
      remove(:sequence)
    end

    alter table("pwm") do
      add(:running_cmd, :string, default: "none")
    end
  end
end
