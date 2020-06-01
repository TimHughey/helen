defmodule Sensor do
  @moduledoc """

  Publix API for Sensors
    a. Devices
    b. Datapoints
    c. Aliases

    * handling of messages received via MQTT
    * querying for datapoint values
  """

  @doc """
    Public API for creating a Sensor Alias
  """
  @doc since: "0.0.16"
  def create_alias(device_or_id, alias_name, opts) do
    alias Sensor.DB
    alias Sensor.Schemas.{Alias, Device}

    # first, find the device to alias
    with %Device{device: dev_name} = dev <- DB.Device.find(device_or_id),
         # create the alias and capture it's name
         {:ok, %Alias{name: name}} <- DB.Alias.create(dev, alias_name, opts) do
      [created: [name: name, device: dev_name]]
    else
      nil -> {:not_found, device_or_id}
      error -> error
    end
  end

  @doc """
    Handles all aspects of processing messages for Sensors

     - if the message hasn't been processed, then attempt to
  """
  @doc since: "0.0.16"
  def handle_message(%{processed: false} = msg_in) do
    alias Sensor.Schemas.Device
    alias Sensor.DB
    alias Fact.Influx

    # the with begins with processing the message through Device.DB.upsert/1
    with %{sensor_device: sensor_device} = msg <- DB.Device.upsert(msg_in),
         # was the upset a success?
         {:ok, %Device{} = dev} <- sensor_device,
         # now process the datapoint
         %{sensor_datapoint: {:ok, _dp}} = msg <- DB.DataPoint.save(dev, msg),
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
    Migrate to v0.0.17 database model

    ### Example
    iex> Sensor.migrate_to("0.0.17")
  """
  @doc since: "0.0.17"
  def migrate_to("0.0.17") do
    alias SensorOld, as: Old

    # named? = fn
    #   %Old{name: name, device: dev_name} -> name != dev_name
    #   _x -> true
    # end

    old = Repo.all(SensorOld)

    for s = %Old{name: name, device: dev} when name != dev <- old do
      create_alias(dev, name, Map.take(s, [:description, :ttl_ms]))
    end
  end
end
