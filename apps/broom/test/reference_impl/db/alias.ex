defmodule BroomTester.DB.Alias do
  @moduledoc false
  use Ecto.Schema

  alias BroomTester.DB.{Command, Device}

  @ttl_default 2000

  schema "broom_alias" do
    field(:name, :string)
    field(:device_id, :integer)
    field(:cmd, :string, default: "unknown")
    field(:description, :string, default: "<none>")
    field(:pio, :integer)
    field(:ttl_ms, :integer, default: @ttl_default)

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
