defmodule Sensor.DB.DataPoint do
  @moduledoc """
  Database functionality for Sensor DataPoint
  """

  alias Sensor.Schemas.{DataPoint, Device}

  def save(%Device{} = dev, %{msg_recv_dt: reading_at} = msg) do
    # NOTE:  we only chheck for :device and :msg_recv_dt as they are
    #        the critical pieces of information for potentially saving
    #        a sensor datapoint

    # NOTE
    #  temporarily map the msg keys to schema keys
    params = %{
      temp_f: Map.get(msg, :tf),
      temp_c: Map.get(msg, :tc),
      relhum: Map.get(msg, :rh),
      moisture: Map.get(msg, :soil),
      reading_at: reading_at
    }

    Map.put(msg, :sensor_datapoint, insert(dev, msg, params))
  end

  def save(msg) when is_map(msg),
    do: Map.put(msg, :sensor_device, {:error, :badmsg})

  defp insert(
         %Device{id: _id} = device,
         %{mtime: _mtime} = _msg,
         params
       )
       when is_list(params) or is_map(params) do
    import Sensor.Schemas.DataPoint, only: [changeset: 2]

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
end
