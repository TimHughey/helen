defmodule Betty do
  @moduledoc false

  alias Betty.{AppError, Connection, Metric}

  # def app_error(module, tags) when is_atom(module) and is_list(tags) do
  #   AppError.new(module, tags) |> AppError.write()
  # end
  #
  # def app_error(%{server_name: module} = pass_through, tags)
  #     when is_atom(module) and is_list(tags) do
  #   app_error(module, tags)
  #
  #   pass_through
  # end
  #
  # def app_error(opts, tags) when is_list(opts) do
  #   Enum.into(opts, %{}) |> app_error(tags)
  # end
  #
  # def app_error(_, _), do: :invalid_args

  def app_error(passthrough, tags) do
    case {passthrough, tags} do
      {x, tags} when is_nil(x) or tags == [] or not is_list(tags) -> :failed
      {x, tags} when is_atom(x) -> AppError.record(x, tags)
      {x, tags} when is_list(x) -> Enum.into(x, %{}) |> app_error(tags)
      {%{server_name: module}, tags} -> app_error(module, tags)
      {%{module: module}, tags} -> app_error(module, tags)
      _ -> :failed
    end

    passthrough
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
  def runtime_metric(passthrough, tags, fields) do
    module = find_module(passthrough)

    if module == :no_module do
      :failed
    else
      tags = [module: module] ++ tags
      Metric.record("runtime", tags, fields)
    end

    passthrough
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

  defp find_module(x) do
    case x do
      module when is_atom(module) -> module
      list when is_list(list) and list != [] -> Enum.into(list, %{}) |> find_module()
      %{server_name: module} -> module |> find_module()
      %{module: module} -> module |> find_module()
      _ -> :no_module
    end
  end
end
