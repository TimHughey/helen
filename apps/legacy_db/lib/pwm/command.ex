defmodule LegacyDb.PulseWidth.Command do
  @moduledoc """
  Database functionality for PulseWidth Command
  """

  use Ecto.Schema

  # alias LegacyDb.PulseWidth.Command, as: Schema
  alias LegacyDb.PulseWidth.{Alias, Device}

  schema "pwm_cmd" do
    field(:refid, Ecto.UUID, autogenerate: true)
    field(:alias_id, :id)
    field(:acked, :boolean, default: false)
    field(:orphan, :boolean, default: false)
    field(:rt_latency_us, :integer)
    field(:sent_at, :utc_datetime_usec)
    field(:ack_at, :utc_datetime_usec)

    belongs_to(:device, Device,
      source: :device_id,
      references: :id,
      foreign_key: :device_id
    )

    belongs_to(:alias, Alias,
      source: :alias_id,
      references: :id,
      foreign_key: :alias_id,
      define_field: false
    )

    timestamps(type: :utc_datetime_usec)
  end
end
