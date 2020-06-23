defmodule Repo.Migrations.AddRemote.Profile do
  use Ecto.Migration

  def change do
    drop_if_exists(table(:remote_profile))

    create_if_not_exists table(:remote_profile) do
      add(:name, :string, null: false)
      add(:version, :uuid, null: false)

      add(:dalsemi_enable, :boolean, null: false, default: true)
      add(:dalsemi_core_stack, :integer, null: false, default: 1536)
      add(:dalsemi_core_priority, :integer, null: false, default: 1)
      add(:dalsemi_discover_stack, :integer, null: false, default: 4096)
      add(:dalsemi_discover_priority, :integer, null: false, default: 12)
      add(:dalsemi_report_stack, :integer, null: false, default: 3072)
      add(:dalsemi_report_priority, :integer, null: false, default: 13)
      add(:dalsemi_convert_stack, :integer, null: false, default: 2048)
      add(:dalsemi_convert_priority, :integer, null: false, default: 13)
      add(:dalsemi_command_stack, :integer, null: false, default: 3072)
      add(:dalsemi_command_priority, :integer, null: false, default: 14)
      add(:dalsemi_core_interval_secs, :integer, null: false, default: 30)
      add(:dalsemi_discover_interval_secs, :integer, null: false, default: 30)
      add(:dalsemi_convert_interval_secs, :integer, null: false, default: 7)
      add(:dalsemi_report_interval_secs, :integer, null: false, default: 7)

      add(:i2c_enable, :boolean, null: false, default: true)
      add(:i2c_use_multiplexer, :boolean, null: false, default: false)
      add(:i2c_core_stack, :integer, null: false, default: 1536)
      add(:i2c_core_priority, :integer, null: false, default: 1)
      add(:i2c_discover_stack, :integer, null: false, default: 4096)
      add(:i2c_discover_priority, :integer, null: false, default: 12)
      add(:i2c_report_stack, :integer, null: false, default: 3072)
      add(:i2c_report_priority, :integer, null: false, default: 13)
      add(:i2c_command_stack, :integer, null: false, default: 3072)
      add(:i2c_command_priority, :integer, null: false, default: 14)
      add(:i2c_core_interval_secs, :integer, null: false, default: 7)
      add(:i2c_discover_interval_secs, :integer, null: false, default: 60)
      add(:i2c_report_interval_secs, :integer, null: false, default: 7)

      add(:pwm_enable, :boolean, null: false, default: true)
      add(:pwm_core_stack, :integer, null: false, default: 1536)
      add(:pwm_core_priority, :integer, null: false, default: 1)
      add(:pwm_discover_stack, :integer, null: false, default: 2048)
      add(:pwm_discover_priority, :integer, null: false, default: 12)
      add(:pwm_report_stack, :integer, null: false, default: 2048)
      add(:pwm_report_priority, :integer, null: false, default: 12)
      add(:pwm_command_stack, :integer, null: false, default: 2048)
      add(:pwm_command_priority, :integer, null: false, default: 14)
      add(:pwm_core_interval_secs, :integer, null: false, default: 10)
      add(:pwm_report_interval_secs, :integer, null: false, default: 10)

      add(:timestamp_task_stack, :integer, null: false, default: 1536)
      add(:timestamp_task_priority, :integer, null: false, default: 0)
      add(:timestamp_watch_stacks, :boolean, null: false, default: false)
      add(:timestamp_core_interval_secs, :integer, null: false, default: 3)
      add(:timestamp_report_interval_secs, :integer, null: false, default: 3600)

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(index(:remote_profile, [:name], unique: true))
  end
end
