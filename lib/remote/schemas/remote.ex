defmodule Remote.Schemas.Remote do
  @moduledoc """
    Schema definition and related functions for Remotes
  """

  use Ecto.Schema

  alias Remote.Schemas.Remote, as: Schema

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
    field(:batt_mv, :integer, default: 0)
    field(:reset_reason, :string)
    field(:bssid, :string)
    field(:ap_rssi, :integer, default: 0)
    field(:ap_pri_chan, :integer, default: 0)
    field(:heap_free, :integer, default: 0)
    field(:heap_min, :integer, default: 0)
    field(:uptime_us, :integer, default: 0)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(%Schema{} = rem, params) do
    import Ecto.Changeset,
      only: [
        cast: 3,
        validate_required: 2,
        validate_format: 3,
        unique_constraint: 2
      ]

    import Common.DB, only: [name_regex: 0]

    rem
    # since this changeset is used by upsert and update we only want to
    # cast the keys of the parameters
    |> cast(params, Map.keys(Enum.into(params, %{})))
    |> validate_required(keys(:required))
    |> validate_format(:host, name_regex())
    |> unique_constraint(:name)
  end

  def keys(:all),
    do:
      Map.from_struct(%Schema{})
      |> Map.drop([:__meta__, :id])
      |> Map.keys()
      |> List.flatten()

  def keys(:cast), do: keys(:all)

  # keys to replace when upserting
  def keys(:replace),
    do: keys_drop(:all, [:host, :name, :profile])

  def keys(:required),
    do:
      keys_drop(:cast, [
        :app_elf_sha256,
        :bssid,
        :build_date,
        :build_time,
        :firmware_vsn,
        :idf_vsn,
        :last_start_at,
        :last_seen_at,
        :reset_reason,
        :updated_at,
        :inserted_at
      ])

  def keys_replace(params),
    do:
      MapSet.difference(
        MapSet.new(Map.keys(params)),
        MapSet.new([:host, :name, :profile])
      )
      |> MapSet.to_list()

  defp keys_drop(base_keys, drop),
    do:
      MapSet.difference(MapSet.new(keys(base_keys)), MapSet.new(drop))
      |> MapSet.to_list()
end
