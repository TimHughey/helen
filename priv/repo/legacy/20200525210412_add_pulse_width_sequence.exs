defmodule Repo.Migrations.AddPulseWidthSequence do
  use Ecto.Migration

  def change do
    alter table("pwm") do
      add(:sequence, :string, default: "none")
    end
  end
end
