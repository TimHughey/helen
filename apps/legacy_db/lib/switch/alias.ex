defmodule LegacyDb.Switch.Alias do
  @moduledoc false

  require Logger
  use Ecto.Schema

  # alias LegacyDb.Switch.Alias, as: Schema
  alias LegacyDb.Switch.Command, as: Command
  alias LegacyDb.Switch.Device, as: Device

  schema "switch_alias" do
    field(:name, :string)
    field(:device_id, :integer)
    field(:description, :string, default: "<none>")
    field(:pio, :integer)
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
