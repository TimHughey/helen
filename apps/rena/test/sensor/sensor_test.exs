defmodule Rena.Sensor.SensorTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag rena: true, sensor_test: true

  alias Rena.Sensor
  alias Rena.Sensor.Range

  import Alfred.NamesAid, only: [sensors_add: 1]

  describe "Rena.Sensor.Range.compare/2 detects" do
    setup [:basic_range_add]

    test "less than low (or equal to) point", %{range_add: range} do
      res = %{temp_f: range.low, relhum: 65.6} |> Range.compare(range)
      should_be_equal(res, :lt_low)
    end

    test "less than (or equal to) mid point", %{range_add: range, mid_pt: mid_pt} do
      res = %{temp_f: mid_pt, relhum: 65.6} |> Range.compare(range)
      should_be_equal(res, :lt_mid)
    end

    test "greater than mid point", %{range_add: range, mid_pt: mid_pt} do
      res = %{temp_f: mid_pt + 0.01, relhum: 65.6} |> Range.compare(range)
      should_be_equal(res, :gt_mid)
    end

    test "greater than (or equal to) high point", %{range_add: range} do
      res = %{temp_f: range.high, relhum: 65.6} |> Range.compare(range)
      should_be_equal(res, :gt_high)
    end

    test "missing datapoint unit", %{range_add: range} do
      res = %{foo: 12.0, bar: 13.0} |> Range.compare(range)
      should_be_equal(res, :invalid)
    end

    test "non number datapoint value", %{range_add: range} do
      res = %{temp_f: "12.0"} |> Range.compare(range)
      should_be_equal(res, :invalid)
    end

    test "invalid Range" do
      res = %{temp_f: 12.0} |> Range.compare(%Range{})
      should_be_equal(res, :invalid)
    end
  end

  describe "Rena.Sensor.range_compare/3" do
    setup [:sensors_add, :basic_range_add]

    @tag sensors_add: [[temp_f: 6.0], [temp_f: 6.1], [temp_f: 0.5], [temp_f: 11.1], [rc: :error, temp_f: 0]]
    test "creates accurate summary", %{range_add: range, sensors: sensors} do
      alias Rena.Sensor.Result

      res = Sensor.range_compare(sensors, range, alfred: AlfredSim)
      good = %Result{gt_mid: 1, gt_high: 1, invalid: 1, lt_low: 1, lt_mid: 1, valid: 4, total: 5}
      should_be_equal(res, good)
    end
  end

  def basic_range_add(_) do
    range = %Range{low: 1.0, high: 11.0, unit: :temp_f}
    mid_pt = (range.high - range.low) / 2 + range.low
    %{range_add: range, mid_pt: mid_pt}
  end
end
