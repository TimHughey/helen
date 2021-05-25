defmodule BroomTester.DB.Device do
  @moduledoc false

  use Ecto.Schema

  alias BroomTester.DB.Alias

  schema "broom_device" do
    field(:device, :string)
    field(:host, :string)
    field(:pio_count, :integer)
    field(:dev_latency_us, :integer, default: 0)
    field(:last_seen_at, :utc_datetime_usec)

    has_many(:aliases, Alias, references: :id, foreign_key: :device_id)

    timestamps(type: :utc_datetime_usec)
  end
end
