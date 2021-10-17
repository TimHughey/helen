defmodule LegacyDb.Remote.Profile do
  @moduledoc """
  Database implementation for Remote Profile
  """

  use Ecto.Schema

  schema "remote_profile" do
    field(:name, :string)
    field(:description, :string)
    field(:version, Ecto.UUID, autogenerate: true)
    field(:watch_stacks, :boolean, default: false)
    field(:core_loop_interval_ms, :integer, default: 1000)
    field(:core_timestamp_ms, :integer, default: 60 * 60 * 1000)

    field(:dalsemi_enable, :boolean, default: true)
    field(:dalsemi_core_stack, :integer, default: 4096)
    field(:dalsemi_core_priority, :integer, default: 1)
    field(:dalsemi_core_interval_ms, :integer, default: 30 * 1000)
    field(:dalsemi_report_stack, :integer, default: 4096)
    field(:dalsemi_report_priority, :integer, default: 5)
    field(:dalsemi_report_interval_ms, :integer, default: 7 * 1000)
    field(:dalsemi_command_stack, :integer, default: 4096)
    field(:dalsemi_command_priority, :integer, default: 14)

    field(:i2c_enable, :boolean, default: true)
    field(:i2c_use_multiplexer, :boolean, default: false)
    field(:i2c_core_stack, :integer, default: 4096)
    field(:i2c_core_priority, :integer, default: 1)
    field(:i2c_core_interval_ms, :integer, default: 30 * 1000)
    field(:i2c_report_stack, :integer, default: 4096)
    field(:i2c_report_priority, :integer, default: 5)
    field(:i2c_report_interval_ms, :integer, default: 7 * 1000)
    field(:i2c_command_stack, :integer, default: 4096)
    field(:i2c_command_priority, :integer, default: 14)

    field(:pwm_enable, :boolean, default: true)
    field(:pwm_core_stack, :integer, default: 4096)
    field(:pwm_core_priority, :integer, default: 14)
    field(:pwm_report_stack, :integer, default: 4096)
    field(:pwm_report_priority, :integer, default: 12)
    field(:pwm_report_interval_ms, :integer, default: 7 * 1000)

    field(:lightdesk_enable, :boolean, default: false)

    timestamps(type: :utc_datetime_usec)
  end
end
