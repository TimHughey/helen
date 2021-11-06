defmodule Betty do
  @moduledoc false

  alias Betty.{Connection, Metric}

  def app_error(module, tags) when is_atom(module) and is_list(tags) do
    alias Betty.AppError

    AppError.new(module, tags) |> AppError.write()
  end

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
  Create and write a single metric to the environment configured database

  """
  @doc since: "0.2.2"
  def metric(measurement, fields, tags) do
    alias Betty.Metric

    Metric.new(measurement, fields, tags)
    |> Metric.write()
  end

  @doc """
  Create and write a runtime metric to the cnvironment configured database

      ### Examples
      iex> tags = [name: "foobar"]
      iex> fields = [val: 1]
      iex> Betty.runtime_metric(SomeModule, tags, fields)
  """
  @doc since: "0.2.3"
  def runtime_metric(module, tags, fields) do
    alias Betty.Metric

    Metric.new("runtime", fields, [module: module] ++ tags) |> Metric.write()
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
  Write a single %Betty.Metric{} to the timeseries database.

  """
  @doc since: "0.2.1"
  def write_metric(%Metric{} = mm) do
    # Instream supports multiple points per write therefore we must wrap this metric in a list
    # and create the points map
    points_map = %{points: [Metric.into_map(mm)]}
    instream_opts = [precision: :nanosecond, async: true]

    # now write the point to the timeseries database
    {Connection.write(points_map, instream_opts), points_map}
  end
end
