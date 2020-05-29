defmodule Sensor.Schemas.Device do
  @moduledoc """
  Definition and database functions for Sensor.Schemes.Device
  """

  require Logger
  use Timex
  use Ecto.Schema

  alias Sensor.Schemas.Device
  alias Sensor.Schemas.DataPoint

  schema "sensor_device" do
    field(:device, :string)
    field(:host, :string)
    field(:dev_latency_us, :integer, default: 0)
    field(:last_seen_at, :utc_datetime_usec)
    field(:discovered_at, :utc_datetime_usec)

    has_many(:datapoints, DataPoint)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Upsert (insert or update) a Sensor.Schemas.Device

  input:
    a. message from an external source or or a map with necessary keys:
       %{device: string, host: string, dev_latency_us: integer, mtime: integer}

  returns input message populated with:
   a. sensor_device: the results of upsert/2
     * {:ok, %Sensor.Schemas.Device{}}
     * {:invalid_changes, %Changeset{}}
     * {:error, actual error results from upsert/2}
  """

  @doc since: "0.0.15"
  def upsert(%{device: _, host: _, dev_latency_us: _, mtime: mtime} = msg) do
    import TimeSupport, only: [from_unix: 1, utc_now: 0]

    params = [:device, :host, :dev_latency_us, :discovered_at, :last_seen_at]

    # create a map of defaults for keys that may not exist in the msg
    params_default = %{
      discovered_at: from_unix(mtime),
      last_seen_at: utc_now()
    }

    # assemble a map of changes
    # NOTE:  the second map passed to Map.merge/2 replaces duplicate keys
    #        in the first map.  in this case we want all available data from
    #        the message however if some isn't available we provide it via
    #        changes_default
    params = Map.merge(params_default, Map.take(msg, params))

    # assemble the return message with the results of upsert/2
    Map.put(msg, :sensor_device, upsert(%Device{}, params))
  end

  def upsert(msg) when is_map(msg),
    do: Map.put(msg, :sensor_device, {:error, :badmsg})

  def upsert(%Device{} = x, params) when is_map(params) or is_list(params) do
    # make certain the params are a map
    params = Enum.into(params, %{})
    # assemble the opts for upsert
    # check for conflicts on :device
    # if there is a conflict only replace keys(:replace)
    opts = [
      on_conflict: {:replace, keys(:replace)},
      returning: true,
      conflict_target: :device
    ]

    cs = changeset(x, params)

    with {cs, true} <- {cs, cs.valid?},
         {:ok, %Device{id: _id} = dev} <- Repo.insert(cs, opts) do
      {:ok, dev}
    else
      {cs, false} ->
        {:invalid_changes, cs}

      {:error, rc} ->
        {:error, rc}

      error ->
        {:error, error}
    end
  end

  def upsert(_x, params) do
    {:error, params}
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
    |> validate_format(:device, name_regex())
    |> validate_format(:host, name_regex())
    |> validate_number(:dev_latency_us, greater_than_or_equal_to: 0)

    # |> unique_constraint(:device, name: :sensor_device_unique_device_index)
  end

  defp keys(:all),
    do:
      Map.from_struct(%Device{})
      |> Map.drop([:__meta__])
      |> Map.keys()
      |> List.flatten()

  defp keys(:cast), do: keys_refine(:all, [:id, :datapoints])

  # defp keys(:upsert), do: keys_refine(:all, [:id, :device])

  defp keys(:replace),
    do:
      keys_refine(:all, [
        :id,
        :device,
        :datapoints,
        :discovered_at,
        :inserted_at
      ])

  defp keys(:required),
    do: keys_refine(:cast, [:updated_at, :inserted_at])

  defp keys_refine(base_keys, drop),
    do:
      MapSet.difference(MapSet.new(keys(base_keys)), MapSet.new(drop))
      |> MapSet.to_list()
end
