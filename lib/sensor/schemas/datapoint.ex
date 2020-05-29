defmodule Sensor.Schemas.DataPoint do
  @moduledoc """
  Definition and database functions for Sensor.Schemas.DataPoint
  """

  require Logger
  use Timex
  use Ecto.Schema

  alias Sensor.Schemas.DataPoint
  alias Sensor.Schemas.Device

  schema "sensor_datapoint" do
    field(:temp_f, :float)
    field(:temp_c, :float)
    field(:relhum, :float)
    field(:moisture, :float)
    field(:reading_at, :utc_datetime_usec)

    belongs_to(:device, Device)

    # timestamps(type: :utc_datetime_usec)
  end

  def save(%{device: _, mtime: _mtime, msg_recv_dt: reading_at} = msg) do
    # NOTE:  we only check that mtime is present in the message
    #        however don't use it since the precision is seconds

    # params = [:temp_f, :temp_c, :relhum, :moisture]

    # NOTE
    #  temporarily map the msg keys to schema keys
    params = %{
      temp_f: Map.get(msg, :tf),
      temp_c: Map.get(msg, :tc),
      relhum: Map.get(msg, :rh),
      moisture: Map.get(msg, :soil),
      reading_at: reading_at
    }

    # send this msg to Switch.Schemas.Device
    with %{sensor_device: device} <- Device.upsert(msg),
         {:ok, %Device{id: _id} = dev} <- device do
      Map.put(msg, :sensor_datapoint, insert(msg, dev, params))
    else
      msg when is_map(msg) ->
        Map.put(msg, :sensor_datapoint, {:error, :bad_msg})

      {rc, error} ->
        Map.put(msg, :sensor_datapoint, {rc, error})
    end
  end

  def save(msg) when is_map(msg),
    do: Map.put(msg, :sensor_device, {:error, :badmsg})

  defp changeset(x, %{device: device} = p) when is_map(p) do
    import Ecto.Changeset,
      only: [
        cast: 3,
        put_assoc: 3,
        validate_required: 2
      ]

    cast(x, p, keys(:cast))
    |> put_assoc(:device, device)
    |> validate_required(keys(:required))
  end

  defp insert(
         %{mtime: _mtime} = _msg,
         %Device{id: _id} = device,
         params
       )
       when is_list(params) or is_map(params) do
    # make certain the params are a map and
    # add the device we'll associate with
    params = Enum.into(params, %{}) |> Map.put(:device, device)

    # assemble the opts for insert
    opts = [returning: true]

    cs = changeset(%DataPoint{}, params)

    with {cs, true} <- {cs, cs.valid?},
         {:ok, %DataPoint{id: _} = datap} <- Repo.insert(cs, opts) do
      {:ok, datap}
    else
      {cs, false} ->
        {:invalid_changes, cs}

      {:error, rc} ->
        {:error, rc}

      error ->
        {:error, error}
    end
  end

  defp keys(:all),
    do:
      Map.from_struct(%DataPoint{})
      |> Map.drop([:__meta__])
      |> Map.keys()
      |> List.flatten()

  defp keys(:cast), do: keys_refine(:all, [:id, :device])
  defp keys(:cast_assoc), do: [:device]

  # defp keys(:upsert), do: keys_refine(:all, [:id, :device])
  defp keys(:required), do: [:device, :reading_at]

  defp keys_refine(base_keys, drop),
    do:
      MapSet.difference(MapSet.new(keys(base_keys)), MapSet.new(drop))
      |> MapSet.to_list()
end
