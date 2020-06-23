defmodule Repo.Migrations.RemoteProfileSchemaRefactor do
  use Ecto.Migration

  def change do
    # all intervals will be represented in milliseconds instead of seconds
    rename(table("remote_profile"), :dalsemi_core_interval_secs,
      to: :dalsemi_core_interval_ms
    )

    rename(table("remote_profile"), :dalsemi_discover_interval_secs,
      to: :dalsemi_discover_interval_ms
    )

    rename(table("remote_profile"), :dalsemi_convert_interval_secs,
      to: :dalsemi_convert_interval_ms
    )

    rename(table("remote_profile"), :dalsemi_report_interval_secs,
      to: :dalsemi_report_interval_ms
    )

    rename(table("remote_profile"), :i2c_core_interval_secs,
      to: :i2c_core_interval_ms
    )

    rename(table("remote_profile"), :i2c_discover_interval_secs,
      to: :i2c_discover_interval_ms
    )

    rename(table("remote_profile"), :i2c_report_interval_secs,
      to: :i2c_report_interval_ms
    )

    rename(table("remote_profile"), :pwm_core_interval_secs,
      to: :pwm_core_interval_ms
    )

    rename(table("remote_profile"), :pwm_report_interval_secs,
      to: :pwm_report_interval_ms
    )

    alter table("remote_profile") do
      # timestamp task no longer exists
      #   functionality incorporated into Core task
      remove(:timestamp_task_stack, :integer, default: 1536)
      remove(:timestamp_task_priority, :integer, default: 0)
      remove(:timestamp_watch_stacks, :boolean, default: false)
      remove(:timestamp_core_interval_secs, :integer, default: 3)
      remove(:timestamp_report_interval_secs, :integer, default: 3600)

      # pwm core task now performs the discover functionality
      remove(:pwm_discover_stack, :integer, default: 2048)
      remove(:pwm_discover_priority, :integer, default: 12)

      add(:watch_stacks, :boolean, null: false, default: false)
      add(:core_loop_interval_ms, :integer, null: false, default: 1000)
      add(:core_timestamp_ms, :integer, null: false, default: 6 * 60 * 1000)

      modify(:dalsemi_core_interval_ms, :integer, default: 30 * 1000)
      modify(:dalsemi_discover_interval_ms, :integer, default: 30 * 1000)
      modify(:dalsemi_convert_interval_ms, :integer, default: 7 * 1000)
      modify(:dalsemi_report_interval_ms, :integer, default: 7 * 1000)
      modify(:i2c_core_interval_ms, :integer, default: 7 * 1000)
      modify(:i2c_discover_interval_ms, :integer, default: 60 * 1000)
      modify(:i2c_report_interval_ms, :integer, default: 7 * 1000)
      modify(:pwm_core_interval_ms, :integer, default: 30 * 1000)
      modify(:pwm_report_interval_ms, :integer, default: 7 * 1000)
    end
  end
end
