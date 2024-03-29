defmodule SallyDatapointTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_datapoint: true

  setup [:dev_alias_add]

  describe "Sally.Datapoint.status/2" do
    @tag dev_alias_add: [auto: :ds, daps: [history: 10, milliseconds: -1]]
    test "calculates correct average (default opts)", ctx do
      assert %{dev_alias: %Sally.DevAlias{name: name}} = ctx

      assert %{status: status} = Sally.Datapoint.status(name, [])
      assert %{points: points} = status

      history_avg = Sally.DatapointAid.avg_daps(ctx, points)

      Enum.each(history_avg, fn {k, v} -> assert_in_delta(v, Map.get(status, k), 0.01) end)
    end

    @tag dev_alias_add: [auto: :ds, daps: [history: 90, seconds: -1]]
    test "calculates correct average (since_ms=60_000, datapoints every second)", ctx do
      assert %{dev_alias: %Sally.DevAlias{name: name}} = ctx

      assert %{status: status} = Sally.Datapoint.status(name, since_ms: 60_000)
      assert %{points: points} = status

      history_avg = Sally.DatapointAid.avg_daps(ctx, points)

      Enum.each(history_avg, fn {k, v} -> assert_in_delta(v, Map.get(status, k), 0.01) end)
    end

    @tag dev_alias_add: [auto: :ds, daps: [history: 20, seconds: -1]]
    test "calculates correct average (since_ms=8_000, datapoints every second)", ctx do
      assert %{dev_alias: %Sally.DevAlias{name: name}} = ctx

      assert %{status: status} = Sally.Datapoint.status(name, since_ms: 8_000)
      assert %{points: points} = status

      history_avg = Sally.DatapointAid.avg_daps(ctx, points)

      Enum.each(history_avg, fn {k, v} -> assert_in_delta(v, Map.get(status, k), 0.01) end)
    end
  end

  describe "Sally.Datapoint.status_query/2" do
    @tag dev_alias_add: [auto: :ds, daps: [history: 10, seconds: 30]]
    test "returns query with preloads for device and host", ctx do
      assert %{dev_alias: %{name: name}} = ctx
      query = Sally.Datapoint.status_query(name, preload: :device_and_host)

      explain = Sally.Repo.explain(:all, query, analyze: true, verbose: true)

      assert explain =~ ~r/Group/
      assert explain =~ ~r/Index Scan/

      measure = Timex.Duration.measure(fn -> Sally.Repo.one(query) end)

      assert {%Timex.Duration{} = duration, %Sally.DevAlias{}} = measure
      ms = Timex.Duration.to_milliseconds(duration)

      assert ms < 50.0
    end
  end
end
