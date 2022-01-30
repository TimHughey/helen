defmodule SallyDatapointTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_datapoint: true

  setup [:dev_alias_add]

  describe "Sally.Datapoint.preload_avg/2" do
    # @tag device_add: [auto: :ds], devalias_add: []
    # @tag datapoint_add: [count: 10, shift_unit: :milliseconds, shift_increment: -1]
    @tag dev_alias_add: [auto: :ds, daps: [history: 10, milliseconds: -1]]
    test "calculates average of :temp_c, :temp_f, :relhum", ctx do
      assert %Sally.DevAlias{datapoints: [%{temp_c: _, temp_f: _, relhum: _}]} =
               Sally.Datapoint.preload_avg(ctx.dev_alias, 10_000)

      dap = Sally.Datapoint.reduce_to_avgs(ctx.dap_history)
      dap2 = avg_daps(ctx.dap_history)

      Enum.each(dap, fn {k, v} -> assert_in_delta(v, Map.get(dap2, k), 0.5) end)
    end

    # @tag device_add: [auto: :ds], devalias_add: []
    # @tag datapoint_add: [count: 10, shift_unit: :milliseconds, shift_increment: -1]
    @tag dev_alias_add: [auto: :ds, daps: [history: 10, milliseconds: -1]]
    test "handles no datapoints", ctx do
      Process.sleep(30)

      assert %{datapoints: []} = Sally.Datapoint.preload_avg(ctx.dev_alias, 20)
    end
  end

  describe "Sally.Datapoint.status/2" do
    @tag dev_alias_add: [auto: :ds, daps: [history: 10, milliseconds: -1]]
    test "calculates correct average (default opts)", ctx do
      assert %{dev_alias: %Sally.DevAlias{name: name}} = ctx

      assert %{datapoints: [%{} = dap]} = Sally.Datapoint.status(name, [])
      dap2 = avg_daps(ctx.dap_history)

      Enum.each(dap, fn {k, v} -> assert_in_delta(v, Map.get(dap2, k), 0.5) end)
    end

    @tag dev_alias_add: [auto: :ds, daps: [history: 90, seconds: -1]]
    test "calculates correct average (since_ms=60_000, datapoints every second)", ctx do
      assert %{dev_alias: %Sally.DevAlias{name: name}} = ctx

      assert %{datapoints: [%{} = dap]} = Sally.Datapoint.status(name, since_ms: 59_999)
      # NOTE: dap_history is generated earliest to most current
      dap2 = Enum.reverse(ctx.dap_history) |> Enum.take(59) |> avg_daps()

      Enum.each(dap, fn {k, v} -> assert_in_delta(v, Map.get(dap2, k), 0.5) end)
    end

    @tag dev_alias_add: [auto: :ds, daps: [history: 20, seconds: -1]]
    test "calculates correct average (since_ms=8_000, datapoints every second)", ctx do
      assert %{dev_alias: %Sally.DevAlias{name: name}} = ctx

      assert %{datapoints: [%{} = dap]} = Sally.Datapoint.status(name, since_ms: 8_000)

      # NOTE: dap_history is generated earliest to most current
      dap2 = Enum.reverse(ctx.dap_history) |> Enum.take(8) |> avg_daps()

      Enum.each(dap, fn {k, v} -> assert_in_delta(v, Map.get(dap2, k), 0.5) end)
    end
  end

  def avg_daps(daps), do: Sally.Datapoint.reduce_to_avgs(daps)
end
