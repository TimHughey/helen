defmodule Rena.Sensor.SensorTest do
  use ExUnit.Case, async: true
  use Alfred.TestAid

  @moduletag rena: true, rena_sensor_test: true

  describe "Rena.Sensor.Range.compare/2 detects" do
    setup [:basic_range_add]

    test "less than low (or equal to) point", %{range_add: range} do
      assert :lt_low = %{temp_f: range.low, relhum: 65.6} |> Rena.Sensor.Range.compare(range)
    end

    test "less than (or equal to) mid point", %{range_add: range, mid_pt: mid_pt} do
      assert :lt_mid = %{temp_f: mid_pt, relhum: 65.6} |> Rena.Sensor.Range.compare(range)
    end

    test "greater than mid point", %{range_add: range, mid_pt: mid_pt} do
      assert :gt_mid = %{temp_f: mid_pt + 0.01, relhum: 65.6} |> Rena.Sensor.Range.compare(range)
    end

    test "greater than (or equal to) high point", %{range_add: range} do
      assert :gt_high = %{temp_f: range.high, relhum: 65.6} |> Rena.Sensor.Range.compare(range)
    end

    test "missing datapoint unit", %{range_add: range} do
      assert :invalid = %{foo: 12.0, bar: 13.0} |> Rena.Sensor.Range.compare(range)
    end

    test "non number datapoint value", %{range_add: range} do
      assert :invalid = Rena.Sensor.Range.compare(%{temp_f: "12.0"}, range)
    end

    test "invalid Range" do
      assert :invalid = Rena.Sensor.Range.compare(%{temp_f: 12.0}, %Rena.Sensor.Range{})
    end
  end

  describe "Rena.Sensor.range_compare/3" do
    setup [:sensors_add, :basic_range_add]

    @tag sensors_add: [
           [temp_f: 6.0],
           [temp_f: 6.1],
           [temp_f: 0.5],
           [temp_f: 11.1],
           [rc: :expired, temp_f: 0]
         ]
    test "creates accurate summary", %{range_add: range, sensors: sensors} do
      res = Rena.Sensor.range_compare(sensors, range, alfred: AlfredSim)

      assert %Rena.Sensor.Result{gt_mid: 1, gt_high: 1, invalid: 1, lt_low: 1, lt_mid: 1, valid: 4, total: 5} =
               res
    end
  end

  def basic_range_add(_) do
    range = %Rena.Sensor.Range{low: 1.0, high: 11.0, unit: :temp_f}
    mid_pt = (range.high - range.low) / 2 + range.low
    %{range_add: range, mid_pt: mid_pt}
  end
end
