defmodule SallyDatapointTest do
  use ExUnit.Case, async: true

  use Sally.TestAid

  @moduletag sally: true, sally_datapoint: true

  setup_all do
    # always create and setup a host
    {:ok, %{host_add: [], host_setup: []}}
  end

  setup [:host_add, :host_setup, :device_add, :devalias_add]
  setup [:datapoint_add]

  describe "Sally.Datapoint.preload_avg/2" do
    @tag device_add: [auto: :ds], devalias_add: []
    @tag datapoint_add: [count: 10, shift_unit: :milliseconds, shift_increment: -1]
    test "calculates average of :temp_c, :temp_f, :relhum", ctx do
      assert %Sally.DevAlias{datapoints: [%{temp_c: _, temp_f: _, relhum: _}]} =
               Sally.Datapoint.preload_avg(ctx.dev_alias, 1000)
    end

    @tag device_add: [auto: :ds], devalias_add: []
    @tag datapoint_add: [count: 10, shift_unit: :milliseconds, shift_increment: -1]
    test "handles no datapoints", ctx do
      Process.sleep(30)

      assert %Sally.DevAlias{datapoints: []} = Sally.Datapoint.preload_avg(ctx.dev_alias, 20)
    end
  end
end
