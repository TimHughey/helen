defmodule Betty do
  @moduledoc false

  @app_error "app_error"
  @runtime "runtime"

  @doc since: "0.2.6"
  def app_error(tags) when is_map(tags) or is_list(tags) do
    tags = if match?(%{}, tags), do: Map.drop(tags, [:__struct__]), else: tags

    Betty.Metric.write(measurement: @app_error, tags: tags, fields: [error: true])
  end

  # def app_error(passthrough, tags) do
  #   alias Betty.AppError
  #
  #   case {passthrough, tags} do
  #     {x, tags} when is_atom(x) and not is_nil(x) -> AppError.record(x, tags)
  #     {x, tags} when is_list(x) and x != [] -> Enum.into(x, %{}) |> app_error(tags)
  #     {%{server_name: module}, tags} -> app_error(module, tags)
  #     {%{module: module}, tags} -> app_error(module, tags)
  #     x -> log_app_error_failed(x)
  #   end
  #
  #   passthrough
  # end
  #
  # @doc """
  # Write an app error metric to the timeseries database
  #
  # Pipelining is supported automatically by returning `:rc` or an alternative
  # specified via opts `[returning: :some_key]`.
  #
  # ## Examples
  # ```
  # # list of tags with :module and returns :rc (by default)
  # [module: Some.Module, rc: :error, equipment: "equipment name"]
  # |> Betty.app_error_v2()
  # #=> :error
  #
  # # list of tags with :server_name
  # [server_name: Some.Server, rc: :failed, other_tag: "important"]
  # |> Betty.app_error_v3()
  # #=> :failed
  #
  # # return the value of a key other than :rc
  # [module: Some.Module, rc: :some_rc]
  # |> Betty.app_error_v3([returning: :some_rc])
  # #=> :some_rc
  # ```
  #
  # > `tags` must include a value for key `:module` __or__ `:server_name`
  #
  # """
  # @doc since: "0.2.6"
  # def app_error_v2(tags, opts \\ [passthrough: :ok])
  #     when is_list(tags)
  #     when is_list(opts) do
  #   # find a value for :module
  #   {mod_or_server, tags_rest} = Keyword.split(tags, [:module, :server_name])
  #   module = mod_or_server[:module] || mod_or_server[:server_name]
  #
  #   Betty.AppError.record(module, tags_rest)
  #
  #   # decide what to return
  #   {return, opts_rest} = Keyword.pop(opts, :return, false)
  #   {passthrough, _} = Keyword.pop(opts_rest, :passthrough, :ok)
  #
  #   if return, do: tags[return], else: passthrough
  # end
  #
  # def app_error_v3(tags) when is_list(tags) or is_map(tags) do
  #   Betty.Metric.write(measurement: "app_error", tags: tags, fields: [error: true])
  # end

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
        case Betty.Connection.run_query("SHOW MEASUREMENTS") |> List.flatten() do
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
  defdelegate metric(opts), to: Betty.Metric, as: :write

  @doc """
  Create and write a runtime metric to the cnvironment configured database

      ### Examples
      iex> tags = [name: "foobar"]
      iex> fields = [val: 1]
      iex> Betty.runtime_metric(SomeModule, tags, fields)
  """
  @doc since: "0.4.0"
  def runtime_metric(tags, fields) do
    Betty.Metric.write(measurement: @runtime, tags: tags, fields: fields)
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
    case Betty.Connection.execute("SHOW SHARDS") do
      %{results: [%{series: series}]} -> Enum.find(series, fn %{name: x} -> x == db end)
      error -> error
    end
  end

  ## Private
  ##
  ##

  defp drop(meas) do
    Betty.Connection.run_query("DROP MEASUREMENT #{meas}")

    String.to_atom(meas)
  end

  defp filter_results(kv_list, opts) do
    case opts[:want] do
      [key] -> kv_list[key]
      [_ | _] = keys -> Keyword.take(kv_list, keys)
      _ -> kv_list
    end
  end

  defp known_fields(meas) do
    Betty.Connection.run_query("SHOW FIELD KEYS FROM #{meas}")
    |> Enum.map(fn [field, type] -> {String.to_atom(field), String.to_atom(type)} end)
  end

  defp known_tags(meas) do
    results = Betty.Connection.run_query("SHOW TAG KEYS FROM #{meas}")

    Enum.reduce(results, [], fn
      [x], acc -> [String.to_atom(x) | acc]
      _x, acc -> acc
    end)
    |> Enum.sort()
  end

  defp known_tag_values(meas, opts) do
    for tag <- known_tags(meas) do
      q = "SHOW TAG VALUES FROM #{meas} WITH KEY=\"#{tag}\""

      for [tag, val] <- Betty.Connection.run_query(q), reduce: [] do
        acc ->
          tag_key = String.to_atom(tag)
          acc_vals = acc[tag_key] || []

          case {tag_key, val} do
            {key, val} when key in [:module, :server_name] -> Module.concat(String.split(val, "."))
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

  # defp rationalize_fields(results) do
  #   for [field, type] <- results, reduce: [] do
  #     acc ->
  #       [{String.to_atom(field), String.to_atom(type)}] ++ acc
  #   end
  #   |> Enum.reverse()
  # end

  # defp rationalize_results(results) do
  #   case results do
  #     x when is_list(x) -> x
  #     _ -> []
  #   end
  # end
end
