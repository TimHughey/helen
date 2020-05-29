defmodule Sensor.Schemas.Alias do
  @moduledoc """
  Defines the schema and database implementation for Sensor Aliases
  """

  require Logger
  use Ecto.Schema

  alias Sensor.Schemas.Alias
  alias Sensor.Schemas.Device

  schema "sensor_alias" do
    field(:name, :string)
    field(:device_id, :integer)
    field(:description, :string, default: "<none>")
    field(:type, :string, default: "auto")
    field(:ttl_ms, :integer, default: 60_000)

    belongs_to(:devices, Device,
      source: :device_id,
      references: :id,
      foreign_key: :device_id,
      define_field: false
    )

    timestamps(type: :utc_datetime_usec)
  end

  def create(%Device{id: id}, name, opts \\ [])
      when is_binary(name) and is_list(opts) do
    #
    # grab keys of interest for the schema (if they exist) and populate the
    # required parameters from the function call
    #
    params =
      Keyword.take(opts, [:description, :type, :ttl_ms])
      |> Enum.into(%{})
      |> Map.merge(%{device_id: id, name: name, device_checked: true})

    upsert(%Alias{}, params)
  end

  def upsert(%Alias{} = x, params) when is_map(params) or is_list(params) do
    # make certain the params are a map
    params = Enum.into(params, %{})
    # assemble the opts for upsert
    # check for conflicts on :device
    # if there is a conflict only replace keys(:replace)
    opts = [
      on_conflict: {:replace, keys(:replace)},
      returning: true,
      conflict_target: :name
    ]

    cs = changeset(x, params)

    with {cs, true} <- {cs, cs.valid?},
         {:ok, %Alias{id: _id} = x} <- Repo.insert(cs, opts) do
      {:ok, x}
    else
      {cs, false} ->
        {:invalid_changes, cs}

      {:error, rc} ->
        {:error, rc}

      error ->
        {:error, error}
    end
  end

  defp changeset(x, p) when is_map(p) do
    import Ecto.Changeset,
      only: [
        cast: 3,
        validate_required: 2,
        validate_format: 3,
        validate_number: 3
      ]

    import Common.DB, only: [name_regex: 0]

    cast(x, p, keys(:cast))
    |> validate_required(keys(:required))
    |> validate_format(:name, name_regex())
    |> validate_number(:ttl_ms, greater_than_or_equal_to: 0)
  end

  defp keys(:all),
    do:
      Map.from_struct(%Alias{})
      |> Map.drop([:__meta__])
      |> Map.keys()
      |> List.flatten()

  defp keys(:cast), do: keys_refine(:all, [:id, :devices])

  # defp keys(:upsert), do: keys_refine(:all, [:id, :device])

  defp keys(:replace),
    do: keys_refine(:all, [:id, :name, :devices, :inserted_at])

  defp keys(:required),
    do:
      keys_refine(:cast, [
        :description,
        :type,
        :ttl_ms,
        :updated_at,
        :inserted_at
      ])

  defp keys_refine(base_keys, drop),
    do:
      MapSet.difference(MapSet.new(keys(base_keys)), MapSet.new(drop))
      |> MapSet.to_list()
end
