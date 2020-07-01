defmodule Sensor do
  @moduledoc """

  Public API for Sensors
    a. Devices
    b. Datapoints
    c. Aliases

    * handling of messages received via MQTT
    * querying for datapoint values
  """

  alias Sensor.DB.{Alias, Device, DataPoint}

  @doc """
    Public API for creating a Sensor Alias
  """
  @doc since: "0.0.16"
  def alias_create(device_or_id, alias_name, opts \\ []) do
    # first, find the device to alias
    with %Device{device: dev_name} = dev <- Device.find(device_or_id),
         # create the alias and capture it's name
         {:ok, %Alias{name: name}} <- Alias.create(dev, alias_name, opts) do
      [created: [name: name, device: dev_name]]
    else
      nil -> {:not_found, device_or_id}
      error -> error
    end
  end

  @doc """
  Alias the most recently inserted device
  """
  @doc since: "0.0.27"
  def alias_most_recent(name) do
    with {device, _inserted_at} <- unaliased_recent() |> hd() do
      alias_create(device, name)
    else
      [] -> {:no_unaliased_devices}
      rc -> rc
    end
  end

  @doc """
  See unaliased/0
  """
  @doc since: "0.0.27"
  def available, do: unaliased()

  @doc """
  See unaliased_recent
  """
  @doc since: "0.0.27"
  def available_recent, do: unaliased_recent()

  @doc """
  Deletes devices that were last updated before UTC now shifted backward by opts.

  Returns a list of the deleted devices.

  ## Examples

      iex> Sensor.delete_unavailable([days: 7])
      ["dead_device1", "dead_device2"]

  """
  @doc since: "0.0.27"
  defdelegate delete_unavailable(opts), to: Device

  @doc """
    Public API for retrieving a list of Sensor Alias names
  """
  @doc since: "0.0.19"
  def names do
    Sensor.DB.Alias.names()
  end

  @doc """
    Public API for retrieving Sensor Alias names that begin with a patteen
  """
  @doc since: "0.0.19"
  def names_begin_with(pattern) when is_binary(pattern) do
    Alias.names_begin_with(pattern)
  end

  @doc """
  Register the caller's pid to receive notifications when the named sensor
  is updated by handle_message
  """
  @doc since: "0.0.26"
  defdelegate notify_register(name), to: Sensor.Notify.Server

  @doc """
    Public API for renaming a Sensor Alias
  """
  @doc since: "0.0.23"
  def rename(name_or_id, new_name, opts \\ []) do
    Alias.rename(name_or_id, new_name, opts)
  end

  @doc """
    Public API for assigning a Sensor Alias to a different Device
  """
  @doc since: "0.0.27"
  def replace(name_or_id, new_dev_name_or_id) do
    Alias.replace(name_or_id, new_dev_name_or_id)
  end

  @doc """
  Replace the existing Alias with the most recently inserted device
  """
  @doc since: "0.0.27"
  def replace_with_most_recent(name) do
    with {device, _inserted_at} <- unaliased_recent() |> hd() do
      replace(name, device)
    else
      [] -> {:no_unaliased_devices}
      rc -> rc
    end
  end

  @doc """
    Public API for retrieving a list of Sensor Device names
  """
  @doc since: "0.0.19"
  def devices do
    Device.devices()
  end

  @doc """
    Public API for retrieving Sensor Device names that begin with a patteen
  """
  @doc since: "0.0.19"
  def devices_begin_with(pattern) when is_binary(pattern) do
    Device.devices_begin_with(pattern)
  end

  ##
  ## DataPoint Access
  ##

  @doc """
  Returns the fahrenheit temperature for a Sensor by alias
  """
  @doc since: "0.0.19"
  def fahrenheit(sensor_alias, opts \\ [])
      when is_binary(sensor_alias) and is_list(opts) do
    with %Alias{device: dev} <- Alias.find(sensor_alias),
         %Device{datapoints: dp} <- Device.load_datapoints(dev, opts),
         val when is_number(val) <- DataPoint.avg_of(dp, :temp_f) do
      val
    else
      _error -> nil
    end
  end

  @doc """
  Returns the relative humidity for a Sensor by alias
  """
  @doc since: "0.0.19"
  def relhum(sensor_alias, opts \\ [])
      when is_binary(sensor_alias) and is_list(opts) do
    with %Alias{device: dev} <- Alias.find(sensor_alias),
         %Device{datapoints: dp} <- Device.load_datapoints(dev, opts),
         val when is_number(val) <- DataPoint.avg_of(dp, :relhum) do
      val
    else
      _error -> nil
    end
  end

  @doc """
  Return a list of devices that are not aliased ordered by inserted at desc
  """
  @doc since: "0.0.27"
  defdelegate unaliased, to: Device

  @doc """
  Return the first five devices that are not aliased order by inserted at desc
  """
  @doc since: "0.0.27"
  def unaliased_recent do
    unaliased() |> Enum.take(5)
  end

  @doc """
    Handles all aspects of processing messages for Sensors

     - if the message hasn't been processed, then attempt to
  """
  @doc since: "0.0.16"
  def handle_message(%{processed: false, type: "sensor"} = msg_in) do
    alias Fact.Influx
    alias Sensor.Notify.Server, as: Server

    # the with begins with processing the message through Device.DB.upsert/1
    with %{device: sensor_device} = msg <- Device.upsert(msg_in),
         # was the upset a success?
         {:ok, %Device{} = dev} <- sensor_device,
         # now process the datapoint
         %{sensor_datapoint: {:ok, _dp}} = msg <- DataPoint.save(dev, msg),
         # technically the message has been processed at this point
         msg <- Map.put(msg, :processed, true),
         # send any notifications requested
         msg <- Server.notify_as_needed(msg),
         # now send the augmented message to the timeseries database
         msg <- Influx.handle_message(msg),
         write_rc <- Map.get(msg, :write_rc),
         {msg, {:processed, :ok}} <- {msg, write_rc} do
      msg
    else
      # it is expected behavior to not write the metric to the timeseries
      # database
      {msg, {:processed, :no_sensor_alias} = _write_rc} ->
        msg

      # we didn't match when attempting to write the timeseries metric
      # this isn't technically a failure however we do want to signal to
      # the caller something is amiss
      {msg, {:processed, :no_match} = write_rc} ->
        ["no match: ", inspect(msg, pretty: true)] |> IO.puts()

        Map.merge(msg, %{
          processed: true,
          warning: :sensor_warning,
          sensor_warning: write_rc
        })

      error ->
        Map.merge(msg_in, %{
          processed: true,
          fault: :sensor_fault,
          sensor_fault: error
        })
    end
  end

  # if the primary handle_message does not match then simply return the msg
  # since it wasn't for sensor and/or has already been processed in the
  # pipeline
  def handle_message(%{} = msg_in), do: msg_in

  @doc """
  Selects devices that were last updated before UTC now shifted backward by opts.

  Returns a list of devices.

  ## Examples

      iex> Sensor.unavailable([days: 7])
      ["dead_device1", "dead_device2"]

  """
  @doc since: "0.0.27"
  def unavailable(opts), do: Device.unavailable(opts)
end
