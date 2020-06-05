defmodule Fact.Influx do
  @moduledoc false

  require Logger
  use Instream.Connection, otp_app: :helen

  @doc """
    Primary entry point for writing timeseries metrics for Sensors

    The message map received by MQTT is forwarded to the Sensor, Remote or
    Switch module for processing.  Those modules then forward the mesasage
    to this function.  If this function finds that the previous module
    successfully processed the message it will write the necesssary
    metrics to the timeseries database.

    NOTE:  This function must return the passed message map (with additional
           keys, if necessary)

  """
  @doc since: "0.0.16"
  def handle_message(%{sensor_datapoint: datapoint, msg_recv_dt: _} = msg) do
    alias Sensor.Schemas.DataPoint, as: Schema
    alias Fact.Sensor

    # begin by confirming the datapoint was saved
    with {:ok, %Schema{} = dp} <- datapoint,
         # add the write_rc key so downstream modules can pattern match
         msg <- Map.put(msg, :write_rc, nil),
         write_rc <- Sensor.write_specific_metric(dp, msg) do
      Map.put(msg, :write_rc, write_rc)
    else
      error ->
        Map.put(msg, :write_rc, {:processed, {:sensor_datapoint_error, error}})
    end
  end

  @doc """
    Primary entry point for writing timeseries metrics for Remotes

    The message map received by MQTT is forwarded to the Sensor, Remote or
    Switch module for processing.  Those modules then forward the mesasage
    to this function.  If this function finds that the previous module
    successfully processed the message it will write the necesssary
    metrics to the timeseries database.

    NOTE:  This function must return the passed message map (with additional
           keys, if necessary)

  """
  @doc since: "0.0.16"
  def handle_message(%{remote_host: remote_host, msg_recv_dt: _} = msg) do
    alias Remote.DB.Remote, as: Schema
    alias Fact.Remote

    # begin by confirming the datapoint was saved
    with {:ok, %Schema{} = rem} <- remote_host,
         # add the write_rc key so downstream modules can pattern match
         msg <- Map.put(msg, :write_rc, nil),
         write_rc <- Remote.write_specific_metric(rem, msg) do
      Map.put(msg, :write_rc, write_rc)
    else
      error ->
        Map.put(msg, :write_rc, {:processed, {:remote_host_error, error}})
    end
  end

  @doc """
  Retrieves measurements for the environment configured database
  """

  @doc since: "0.0.16"
  def measurements do
    with vals when is_list(vals) <- run_query("SHOW MEASUREMENTS") do
      List.flatten(vals)
    else
      error -> error
    end
  end

  @doc """
  Runs a query and returns the values from the result
  """

  @doc since: "0.0.16"
  def run_query(q) when is_binary(q) do
    with %{results: results} when is_list(results) <- query(q),
         %{series: series} <- hd(results),
         %{values: vals} <- hd(series) do
      vals
    else
      error -> error
    end
  end

  @doc """
    Retrieves a map of all Influx Shards for the specified database

      ### Examples
      iex> Fact.Influx.shards("database")
      %{columns: ["binary", "binary", ...],
        name: "database name",
        values: [<matches columns>]}


  """
  @doc since: "0.0.15"
  def shards(db) do
    Fact.Influx.execute("show shards")
    |> Map.get(:results)
    |> hd()
    |> Map.get(:series)
    |> Enum.find(fn x -> Map.get(x, :name, db) == db end)
  end

  ###
  ###
  ###

  def normalize_readings(nil), do: %{}

  def normalize_readings(%{temp_f: nil, temp_c: nil} = x), do: x

  def normalize_readings(%{} = r) do
    has_tc = Map.has_key?(r, :tc)
    has_tf = Map.has_key?(r, :tf)

    r =
      if Map.has_key?(r, :rh),
        do: Map.put(r, :rh, Float.round(r.rh * 1.0, 3)),
        else: r

    r = if has_tc, do: Map.put(r, :tc, Float.round(r.tc * 1.0, 3)), else: r
    r = if has_tf, do: Map.put(r, :tf, Float.round(r.tf * 1.0, 3)), else: r

    cond do
      has_tc and has_tf -> r
      has_tc -> Map.put_new(r, :tf, Float.round(r.tc * (9.0 / 5.0) + 32.0, 3))
      has_tf -> Map.put_new(r, :tc, Float.round(r.tf - 32 * (5.0 / 9.0), 3))
      true -> r
    end
  end
end
