defmodule LegacyDb.Switch.Command do
  @moduledoc """
  Database functionality for Switch Command
  """

  use Ecto.Schema

  # alias LegacyDb.Switch.Command, as: Schema
  alias LegacyDb.Switch.{Alias, Device}

  schema "switch_command" do
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
