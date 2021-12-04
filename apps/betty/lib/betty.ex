defmodule Betty do
  @moduledoc false

  alias Betty.{Connection, Metric}

  def app_error(passthrough, tags) do
    alias Betty.AppError

    case {passthrough, tags} do
      {x, tags} when is_atom(x) and not is_nil(x) -> AppError.record(x, tags)
      {x, tags} when is_list(x) and x != [] -> Enum.into(x, %{}) |> app_error(tags)
      {%{server_name: module}, tags} -> app_error(module, tags)
      {%{module: module}, tags} -> app_error(module, tags)
      x -> log_app_error_failed(x)
    end

    passthrough
  end

  @doc """
  Write an app error metric to the timeseries database

  Pipelining is supported automatically by returning `:rc` or an alternative
  specified via opts `[returning: :some_key]`.

  ## Examples
  ```
  # list of tags with :module and returns :rc (by default)
  [module: Some.Module, rc: :error, equipment: "equipment name"]
  |> Betty.app_error_v2()
  #=> :error

  # list of tags with :server_name
  [server_name: Some.Server, rc: :failed, other_tag: "important"]
  |> Betty.app_error_v3()
  #=> :failed

  # return the value of a key other than :rc
  [module: Some.Module, rc: :some_rc]
  |> Betty.app_error_v3([returning: :some_rc])
  #=> :some_rc
  ```

  > `tags` must include a value for key `:module` __or__ `:server_name`

  """
  @doc since: "0.2.6"
  def app_error_v2(tags, opts \\ [passthrough: :ok])
      when is_list(tags)
      when is_list(opts) do
    alias Betty.AppError

    # find a value for :module
    {mod_or_server, tags_rest} = Keyword.split(tags, [:module, :server_name])
    module = mod_or_server[:module] || mod_or_server[:server_name]

    AppError.record(module, tags_rest)

    # decide what to return
    {return, opts_rest} = Keyword.pop(opts, :return, false)
    {passthrough, _} = Keyword.pop(opts_rest, :passthrough, :ok)

    if return, do: tags[return], else: passthrough
  end

  @doc """
  Measurement exploration and maintenance

  ## Examples
  ```
  Betty.measurement(:app_error, :tags)
  #=> ["module", "name", ...]

  Betty.measurement(:app_error, :tag_values)
  #=> [name: ["name1", "name2", ...], module: [Some.Mod1, Some.Mod2, ...], ...]

  Betty.measurement(:app_error, :drop)
  #=> :app_error
  ```
  """
  @doc since: "0.2.5"
  def measurement(meas, action \\ :tags, opts \\ [])
      when action in [:drop, :tags, :tag_values]
      when is_list(opts) do
    meas = if(is_atom(meas), do: to_string(meas), else: meas)

    case action do
      :drop -> drop(meas)
      :tags -> known_tags(meas)
      :fields -> known_fields(meas)
      :tag_values -> known_tag_values(meas, opts)
      _ -> [options: [:drop, :tags, :tag_values]]
    end
  end

  @doc """
  Retrieves measurements for the environment configured database

  ## Examples
  ```
  Betty.measurements(:show)
  #=> [:app_error, :runtime, ...]

  Betty.measurements(:drop_all)
  #=> [:app_error, :runtime, ...]
  ```
  """
  @doc since: "0.2.2"
  def measurements(action \\ :show) do
    case action do
      :show ->
        case Connection.run_query("SHOW MEASUREMENTS") |> List.flatten() do
          [_ | _] = vals -> Enum.map(vals, fn x -> String.to_atom(x) end)
          error -> [error]
        end

      :drop_all ->
        for meas <- measurements(:show) do
          measurement(meas, :drop)
        end
    end
  end

  @doc """
  Create and write a single metric to the environment configured database

  """
  @doc since: "0.2.2"
  def metric(measurement, fields, tags) do
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
      [measurement: "runtime", tags: [module: module] ++ tags, fields: fields]
      |> Metric.new()
      |> Metric.write()
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
  Write a generic measurement with tags and fields

  ## Examples
  ```
  # via a list of opts
  [measurement: "generic", tags: [tag1: "val"], fields: [field: :val]]
  |> Betty.write()
  #=> :ok

  # via a list of opts include what to return
  [return: [], measurement: "generic", tags: [tag1: "val"], fields: [field: :val]]
  |> Betty.write()
  #=> []

  # when required opts are missing a warning message is logged
  [tags: [tag1: "val"], fields: [field: :val]]
  |> Betty.write()
  #=> :ok

  ```
  """
  @doc since: "0.2.6"
  def write(opts) when is_list(opts) do
    want_keys = [:measurement, :tags, :fields]
    {metric_kv, _} = Keyword.split(opts, want_keys)

    if length(metric_kv) == 3 do
      metric_kv |> Metric.new() |> Metric.write()
    else
      require Logger

      missing_keys = want_keys -- Keyword.keys(metric_kv)

      ["missing keys: ", inspect(missing_keys), "\n", inspect(opts, pretty: true)]
      |> IO.iodata_to_binary()
      |> Logger.warn()
    end

    # return the passthrough if specified
    opts[:return] || :ok
  end

  ## Private
  ##
  ##

  defp drop(meas) do
    "DROP MEASUREMENT #{meas}"
    |> Connection.run_query()

    String.to_atom(meas)
  end

  defp filter_results(kv_list, opts) do
    case opts[:want] do
      [key] -> kv_list[key]
      [_ | _] = keys -> Keyword.take(kv_list, keys)
      _ -> kv_list
    end
  end

  defp find_module(x) do
    case x do
      module when is_atom(module) -> module
      x when is_list(x) and x != [] -> Enum.into(x, %{}) |> find_module()
      %{server_name: module} -> module |> find_module()
      %{module: module} -> module |> find_module()
      _ -> :no_module
    end
  end

  defp known_fields(meas) do
    Connection.run_query("SHOW FIELD KEYS FROM #{meas}")
    |> rationalize_fields()
  end

  defp known_tags(meas) do
    Connection.run_query("SHOW TAG KEYS FROM #{meas}")
    |> rationalize_results()
    |> List.flatten()
    |> Enum.map(fn tag -> String.to_atom(tag) end)
  end

  defp known_tag_values(meas, opts) do
    for tag <- known_tags(meas) do
      q = "SHOW TAG VALUES FROM #{meas} WITH KEY=\"#{tag}\""

      for [tag, val] <- Connection.run_query(q), reduce: [] do
        acc ->
          tag_key = String.to_atom(tag)
          acc_vals = acc[tag_key] || []

          case {tag_key, val} do
            {key, val} when key in [:module, :server_name] -> to_module(val)
            {_, "true"} -> true
            {_, "false"} -> false
            kv -> kv
          end
          |> then(fn final_val -> put_in(acc, [tag_key], [final_val] ++ acc_vals) end)
      end
    end
    |> Enum.map(fn [{k, vals}] -> {k, Enum.sort(vals)} end)
    |> filter_results(opts)
  end

  defp log_app_error_failed({passthrough, tags}) do
    require Logger

    ["\n", "passthrough: ", inspect(passthrough, pretty: true), "\n", "tags: ", inspect(tags, pretty: true)]
    |> IO.iodata_to_binary()
    |> Logger.error()

    :failed
  end

  defp rationalize_fields(results) do
    for [field, type] <- results, reduce: [] do
      acc ->
        [{String.to_atom(field), String.to_atom(type)}] ++ acc
    end
    |> Enum.reverse()
  end

  defp rationalize_results(results) do
    case results do
      x when is_list(x) -> x
      _ -> []
    end
  end

  # defp to_float(val) do
  #   case Float.parse(val) do
  #     {float, ""} -> float
  #     _x -> val
  #   end
  # catch
  #   _, _ -> val
  # end

  defp to_module(val), do: String.split(val, ".") |> Module.concat()
end
