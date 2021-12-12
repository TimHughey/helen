defmodule SallyDatapointTest do
  # can not use async: true due to indirect use of Sally.device_latest/1
  use ExUnit.Case
  use Should
  use Sally.TestAid

  @moduletag sally: true, sally_datapoint: true

  alias Sally.{Datapoint, DevAlias}

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
      dev_alias = Datapoint.preload_avg(ctx.dev_alias, 1000) |> Should.Be.struct(DevAlias)

      # NOTE: Should.Be.List.with_length/2 automatically unwraps single item lists
      datapoints = Should.Be.List.with_length(dev_alias.datapoints, 1)
      Should.Be.Map.with_size(datapoints, 3)
    end

    @tag device_add: [auto: :ds], devalias_add: []
    @tag datapoint_add: [count: 10, shift_unit: :milliseconds, shift_increment: -1]
    test "handles no datapoints", ctx do
      Process.sleep(30)
      dev_alias = Datapoint.preload_avg(ctx.dev_alias, 20) |> Should.Be.struct(DevAlias)

      Should.Be.List.with_length(dev_alias.datapoints, 0)
    end
  end
end
