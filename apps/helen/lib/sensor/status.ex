defmodule Sensor.Status do
  require Ecto.Query
  alias Ecto.Query

  alias Sensor.DB.{Alias, DataPoint}

  @since_default_ms 60_000 * 5

  def make_status(%Alias{} = a, opts) do
    status(a, opts)
  end

  defp status(%Alias{} = a, opts) do
    %{name: a.name, seen_at: a.device.last_seen_at, ttl_ms: opts[:ttl_ms] || a.ttl_ms, values: []}
    # perform the ttl check before requesting status from Datapoint to
    # avoid querying the database if the ttl is expired
    |> ttl_check()
    |> load_datapoints(a, opts)
    |> calc_avg_of()
    # perform the ttl check again using the (potentially) updated seen_at based on datapoints
    |> ttl_check()
  end

  # (2 of 2) nominal case, we have data points
  defp calc_avg_of(%{datapoints: datapoints} = status_map) when datapoints != [] do
    value_map = avg_of(datapoints)
    # override the initial seen_at with the reading_at of the first DataPoint to enhance ttl check precision
    seen_at = Enum.at(datapoints, 0).reading_at

    %{status_map | values: Map.keys(value_map), seen_at: seen_at}
    # datapoints were used to calculate the average, no need to return them
    |> Map.delete(:datapoints)
    |> Map.merge(value_map)
  end

  # (2 of 2) no data points, nothing to do
  defp calc_avg_of(status_map), do: status_map

  # (1 of 2) ttl is expired, don't load datapoints
  defp load_datapoints(%{ttl_expired: true} = status_map, _, _), do: status_map

  # (2 of 2) ttl isn't expired, load datapoints for status
  defp load_datapoints(status_map, %Alias{} = a, opts) do
    since_ms = EasyTime.iso8601_duration_to_ms(opts[:since]) || @since_default_ms
    since_dt = DateTime.utc_now() |> DateTime.add(since_ms * -1, :millisecond)

    q = Query.from(dp in DataPoint, where: dp.reading_at >= ^since_dt, order_by: [desc: dp.reading_at])
    a = Repo.preload(a, datapoints: q)

    put_in(status_map, [:datapoints], a.datapoints)
  end

  # (1 of 2) DataPoint has relhum
  defp avg_of([%DataPoint{relhum: rh} | _] = datapoints) when is_number(rh) do
    for %DataPoint{temp_c: tc, relhum: rh} <- datapoints, reduce: {0, 0, 0} do
      {count, temp_c_sum, relhum_sum} -> {count + 1, temp_c_sum + tc, relhum_sum + rh}
    end
    |> avg_of_value_map()
  end

  # (2 of 2) DataPoint is just temperature
  defp avg_of([%DataPoint{} | _] = datapoints) do
    for %DataPoint{temp_c: tc} <- datapoints, reduce: {0, 0} do
      {count, temp_c_sum} -> {count + 1, temp_c_sum + tc}
    end
    |> avg_of_value_map()
  end

  defp avg_of_value_map(avg_of_result) do
    case avg_of_result do
      {x, tc_sum, rh_sum} -> %{temp_c: round3(tc_sum / x), relhum: round3(rh_sum / x), count: x}
      {x, tc_sum} -> %{temp_c: round3(tc_sum / x), count: x}
    end
  end

  defp round3(val), do: Float.round(val, 3)

  # (1 of 2) ttl already checked and found expired
  defp ttl_check(%{ttl_expired: true} = m), do: m

  # (2 of 2) nominal case
  defp ttl_check(%{ttl_ms: ttl_ms, seen_at: seen_at} = m) do
    ttl_dt = DateTime.utc_now() |> DateTime.add(ttl_ms * -1, :millisecond)

    case DateTime.compare(seen_at, ttl_dt) do
      :lt -> put_in(m, [:ttl_expired], true)
      x when x in [:gt, :eq] -> m
    end
  end
end
