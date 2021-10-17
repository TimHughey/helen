defmodule LegacyDb.Remote do
  @moduledoc """
  Database implementation for Remote
  """

  use Ecto.Schema

  schema "remote" do
    field(:host, :string)
    field(:name, :string)
    field(:profile, :string, default: "default")
    field(:firmware_vsn, :string)
    field(:firmware_etag, :string, default: "<none>")
    field(:idf_vsn, :string)
    field(:app_elf_sha256, :string)
    field(:build_date, :string)
    field(:build_time, :string)
    field(:last_start_at, :utc_datetime_usec)
    field(:last_seen_at, :utc_datetime_usec)
    field(:reset_reason, :string)
    field(:bssid, :string)
    field(:ap_rssi, :integer, default: 0)
    field(:ap_pri_chan, :integer, default: 0)
    field(:heap_free, :integer, default: 0)
    field(:heap_min, :integer, default: 0)
    field(:uptime_us, :integer, default: 0)

    timestamps(type: :utc_datetime_usec)
  end
end
