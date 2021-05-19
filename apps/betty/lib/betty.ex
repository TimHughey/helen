defmodule Betty do
  @moduledoc false

  alias Betty.{Connection, Metric}

  @doc """
  Retrieves measurements for the environment configured database

  """
  @doc since: "0.2.1"
  def measurements do
    case Connection.run_query("SHOW MEASUREMENTS") do
      vals when is_list(vals) -> List.flatten(vals)
      error -> error
    end
  end

  @doc """
    Retrieves a map of all Influx Shards for the specified database

      ### Examples
      iex> Betty.shards("database")
      %{columns: ["binary", "binary", ...],
        name: "database name",
        values: [<matches columns>]}

  """
  @doc since: "0.2.1"
  def shards(db) do
    case Connection.execute("SHOW SHARDS") do
      %{results: [%{series: series}]} -> Enum.find(series, fn %{name: x} -> x == db end)
      error -> error
    end
  end

  @doc """
  Wrote a single %Betty.Metric{} to the timeseries database.

  """
  @doc since: "0.2.1"
  def write_metric(%Metric{} = mm) do
    # Instream supports multiple points per write therefore we must wrap this metric in a list
    # and create the points map
    points_map = %{points: [Metric.into_map(mm)]}
    instream_opts = [precision: :nanosecond, async: true]

    # now erite the point to the timeseries database
    Connection.write(points_map, instream_opts)
  end
end
