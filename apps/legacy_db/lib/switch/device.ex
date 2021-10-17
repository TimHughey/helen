defmodule LegacyDb.Switch.Device do
  @moduledoc """
  Database functionality for Switch Device
  """

  use Ecto.Schema

  alias LegacyDb.Switch.Alias, as: Alias
  alias LegacyDb.Switch.Command, as: Command
  # alias LegacyDb,Switch.Device, as: Schema

  schema "switch_device" do
    field(:device, :string)
    field(:host, :string)

    embeds_many :states, State do
      field(:pio, :integer, default: nil)
      field(:state, :boolean, default: false)
    end

    field(:dev_latency_us, :integer)
    field(:ttl_ms, :integer, default: 60_000)
    field(:last_seen_at, :utc_datetime_usec)
    field(:last_cmd_at, :utc_datetime_usec)
    field(:discovered_at, :utc_datetime_usec)

    has_many(:cmds, Command, foreign_key: :device_id, references: :id)

    has_many(:aliases, Alias, foreign_key: :device_id, references: :id)

    timestamps(type: :utc_datetime_usec)
  end
end
