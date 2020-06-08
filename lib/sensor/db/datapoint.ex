defmodule Sensor.DB.DataPoint do
  @moduledoc """
  Database functionality for Sensor DataPoint
  """

  use Ecto.Schema

  alias Sensor.DB.{DataPoint, Device}

  schema "sensor_datapoint" do
    field(:temp_f, :float)
    field(:temp_c, :float)
    field(:relhum, :float)
    field(:capacitance, :float)
    field(:reading_at, :utc_datetime_usec)

    belongs_to(:device, Device)

    # timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Returns the average of a specific field (column) from a list of %DataPoints{}
  """

  @doc since: "0.9.19"
  def avg_of(datapoints, column)
      when is_list(datapoints) and
             column in [:temp_f, :temp_c, :relhum, :capacitance] do
    vals =
      Enum.into(datapoints, [], fn
        %DataPoint{} = dp -> Map.get(dp, column)
        _x -> nil
      end)

    with count when count > 0 <- Enum.count(vals),
         true <- Enum.all?(vals, &is_number/1) do
      Float.round(Enum.sum(vals) / count, 3)
    else
      _anything -> nil
    end
  end

  @doc since: "0.0.16"
  def changeset(x, %{device: device} = p) when is_map(p) do
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

  @doc since: "0.0.16"
  def keys(:all),
    do:
      Map.from_struct(%DataPoint{})
      |> Map.drop([:__meta__])
      |> Map.keys()
      |> List.flatten()

  def keys(:cast), do: keys_refine(:all, [:id, :device])
  def keys(:cast_assoc), do: [:device]

  # defp keys(:upsert), do: keys_refine(:all, [:id, :device])
  def keys(:required), do: [:device, :reading_at]

  defp keys_refine(base_keys, drop),
    do:
      MapSet.difference(MapSet.new(keys(base_keys)), MapSet.new(drop))
      |> MapSet.to_list()

  def save(%Device{} = dev, %{msg_recv_dt: reading_at} = msg) do
    # NOTE:  we only chheck for :device and :msg_recv_dt as they are
    #        the critical pieces of information for potentially saving
    #        a sensor datapoint

    ### START TEMPORARY LEGACY SUPPORT

    # NOTE:
    #   for short-term backward compatibility with older remote firmware
    #   we look for data using the old key names and the new key names
    #
    #   to do this we:
    #     1. manually map the old keys into params
    #     2. use Map.take/2 with the new key names
    #     3. then merge the two maps

    # NOTE
    #  temporarily map the msg keys to schema keys
    params_legacy = %{
      temp_f: Map.get(msg, :tf),
      temp_c: Map.get(msg, :tc),
      relhum: Map.get(msg, :rh),
      capacitance: Map.get(msg, :cap),
      reading_at: reading_at
    }

    params_new =
      Map.take(msg, [:temp_f, :temp_c, :relhum, :capacitance, :reading_at])

    params = Map.merge(params_legacy, params_new)

    ### END TEMPORARY LEGACY SUPPORT

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
