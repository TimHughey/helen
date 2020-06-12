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
    Public API for renaming a Sensor Alias
  """
  @doc since: "0.0.23"
  def rename(name_or_id, new_name, opts \\ []) do
    Alias.rename(name_or_id, new_name, opts)
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
    Handles all aspects of processing messages for Sensors

     - if the message hasn't been processed, then attempt to
  """
  @doc since: "0.0.16"
  def handle_message(%{processed: false, type: "sensor"} = msg_in) do
    alias Fact.Influx

    # the with begins with processing the message through Device.DB.upsert/1
    with %{sensor_device: sensor_device} = msg <- Device.upsert(msg_in),
         # was the upset a success?
         {:ok, %Device{} = dev} <- sensor_device,
         # now process the datapoint
         %{sensor_datapoint: {:ok, _dp}} = msg <- DataPoint.save(dev, msg),
         # technically the message has been processed at this point
         msg <- Map.put(msg, :processed, true),
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
end
