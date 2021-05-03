defmodule Repo.Migrations.AddPulseWidthRunningCommand do
  use Ecto.Migration

  @cmd_field_size 32

  def change do
    alter table("pwm_cmd") do
      add(:requested_cmd, :string, size: @cmd_field_size)
    end

    alter table("pwm_device") do
      add(:running_cmd, :string, size: @cmd_field_size)
    end
  end
end
