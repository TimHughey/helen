defmodule Fact.Influx do
  @moduledoc false

  require Logger
  use Instream.Connection, otp_app: :helen

  @doc """
    Primary entry point for writing timeseries metrics for Sensors or Remotes

    The message map received by MQTT is forwarded to the Sensor, Remote or
    Switch module for processing.  Those modules then forward the mesasage
    to this function.  If this function finds that the previous module
    successfully processed the message it will write the necesssary
    metrics to the timeseries database.

    NOTE:  This function must return the passed message map (with additional
           keys, if necessary)

  """
  @doc since: "0.0.16"
  # def handle_message(%{sensor_datapoint: datapoint, msg_recv_dt: _} = msg) do
  #   alias Sensor.DB.DataPoint, as: Schema
  #   alias Sensor.Fact
  #
  #   # begin by confirming the datapoint was saved
  #   with {:ok, %Schema{} = dp} <- datapoint,
  #        # add the write_rc key so downstream modules can pattern match
  #        msg <- Map.put(msg, :write_rc, nil),
  #        write_rc <- Fact.write_specific_metric(dp, msg) do
  #     Map.put(msg, :write_rc, write_rc)
  #   else
  #     error ->
  #       Map.put(msg, :write_rc, {:processed, {:sensor_datapoint_error, error}})
  #   end
  # end

  def handle_message(%{remote_host: remote_host, msg_recv_dt: _} = msg) do
    alias Remote.DB.Remote, as: Schema
    alias Remote.Fact

    # begin by confirming the datapoint was saved
    with {:ok, %Schema{} = rem} <- remote_host,
         # add the write_rc key so downstream modules can pattern match
         msg <- Map.put(msg, :write_rc, nil),
         write_rc <- Fact.write_specific_metric(rem, msg) do
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
    case run_query("SHOW MEASUREMENTS") do
      vals when is_list(vals) -> List.flatten(vals)
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
end
