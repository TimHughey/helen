defmodule LegacyDb.PulseWidth.Alias do
  @moduledoc """
  Database implementation of PulseWidth Aliases
  """

  use Ecto.Schema

  # alias LegacyDb.PulseWidth.Alias, as: Schema
  alias LegacyDb.PulseWidth.{Command, Device}

  schema "pwm_alias" do
    field(:name, :string)
    field(:device_id, :integer)
    field(:description, :string, default: "<none>")
    field(:capability, :string, default: "pwm")
    field(:ttl_ms, :integer, default: 60_000)

    belongs_to(:device, Device,
      source: :device_id,
      references: :id,
      foreign_key: :device_id,
      define_field: false
    )

    has_many(:cmds, Command,
      references: :id,
      foreign_key: :alias_id
    )

    timestamps(type: :utc_datetime_usec)
  end
end
