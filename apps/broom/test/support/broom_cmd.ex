defmodule BroomTester.DB.Command do
  @moduledoc false

  use Ecto.Schema

  alias BroomTester.DB.Alias
  # alias BroomTester.DB.Command, as: Schema

  schema "broom_cmd" do
    field(:refid, Ecto.UUID, autogenerate: true)
    field(:cmd, :string, default: "unknown")
    field(:acked, :boolean, default: false)
    field(:orphan, :boolean, default: false)
    field(:rt_latency_us, :integer)
    field(:sent_at, :utc_datetime_usec)
    field(:ack_at, :utc_datetime_usec)

    belongs_to(:alias, Alias)

    timestamps(type: :utc_datetime_usec)
  end
end
