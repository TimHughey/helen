defmodule Repo.Migrations.MatchPwmToSwitchDesign do
  use Ecto.Migration

  def change do
    alter table(:pwm_alias) do
      # never implemented and won't be
      remove(:capability, :string, size: 20, default: "<pwm", null: false)

      add(:pio, :integer, null: false)
      add(:remote_cmd, :string, size: 32, null: false, default: "unknown")
      add(:duty, :integer, default: 0, null: false)
      add(:duty_max, :integer, default: 8191, null: false)
      add(:duty_min, :integer, default: 0, null: false)
    end

    drop_if_exists(constraint(:pwm_cmd, "pwm_cmd_device_id_fkey"))

    alter table(:pwm_cmd) do
      remove(:device_id, :bigint)
    end

    alter table(:pwm_device) do
      add(:pio_count, :integer, null: false)

      remove(:duty, :integer, default: 0, null: false)
      remove(:duty_max, :integer, default: 4095, null: false)
      remove(:duty_min, :integer, default: 0, null: false)
      remove(:last_cmd_at, :utc_datetime_usec)
      remove(:ttl_ms, :integer, default: 60_000, null: false)
    end
  end
end
