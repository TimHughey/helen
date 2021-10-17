defmodule LegacyDb.PulseWidth.Device do
  @moduledoc """
  Database implementation of PulseWidth devices
  """

  require Logger

  alias LegacyDb.PulseWidth.Alias, as: Alias
  alias LegacyDb.PulseWidth.Command, as: Command
  # alias LegacyDb.PulseWidth.Device, as: Schema

  use Ecto.Schema

  schema "pwm_device" do
    field(:device, :string)
    field(:host, :string)
    field(:duty, :integer, default: 0)
    field(:duty_max, :integer, default: 8191)
    field(:duty_min, :integer, default: 0)
    field(:dev_latency_us, :integer, default: 0)
    field(:last_seen_at, :utc_datetime_usec)
    field(:discovered_at, :utc_datetime_usec)
    field(:last_cmd_at, :utc_datetime_usec)

    has_many(:cmds, Command, foreign_key: :device_id)
    has_one(:_alias_, Alias, references: :id, foreign_key: :device_id)

    timestamps(type: :utc_datetime_usec)
  end
end
