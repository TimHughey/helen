defmodule Rena.Sensor2.Test do
  use ExUnit.Case, async: true
  use Rena.TestAid

  @moduletag rena: true, rena_sensor2_test: true

  @tz "America/New_York"

  setup [:sensor_group_add]

  describe "Rena.Sensor.new/1" do
    @tag sensor_group_add: []
    test "creates new Sensor from fields", ctx do
      assert %{sensor_group: sensor} = ctx
      assert %Rena.Sensor{reading_at: nil, tally: %{}} = sensor
      assert %{names: names, range: range, valid_when: valid_when} = sensor
      assert Enum.count(names) == 4
      assert Enum.all?(names, &match?(<<_::binary>>, &1))

      assert %{low: 1.0, high: 11.0, unit: :temp_f} = range
      assert %{valid: 2, total: 4} = valid_when
    end
  end

  describe "Rena.Sensor.tally_names/2" do
    @tag sensor_group_add: [
           name: [temp_f: 6.0],
           name: [temp_f: 6.1],
           name: [temp_f: 0.5],
           name: [temp_f: 11.1],
           name: [rc: :expired, temp_f: 0]
         ]
    test "creates accurate summary", ctx do
      assert %{sensor_group: sensor} = ctx

      sensor = Rena.Sensor.tally(sensor, timezone: @tz)

      assert %Rena.Sensor{reading_at: %DateTime{}, tally: tally} = sensor

      want_tally = %{gt_high: 1, gt_mid: 1, invalid: 1, lt_low: 1, lt_mid: 1, total: 5, valid: 4}
      assert ^want_tally = tally
    end
  end

  describe "Rena.Sensor.next_action/2" do
    @tag sensor_group_add: [
           name: [temp_f: 6.0],
           name: [temp_f: 6.1],
           name: [temp_f: 0.5],
           name: [temp_f: 11.1],
           name: [rc: :expired, temp_f: 0]
         ]
    test "handles :lower case", ctx do
      assert %{sensor_group: sensor} = ctx
      assert %{equipment: %{name: equipment}} = ctx

      sensor = Rena.Sensor.tally(sensor, timezone: @tz)

      assert %Rena.Sensor{reading_at: %DateTime{}} = sensor

      next_action = Rena.Sensor.next_action(equipment, sensor, [])
      assert {:lower, "off"} = next_action
    end

    @tag sensor_group_add: [
           name: [temp_f: 6.0],
           name: [temp_f: 6.1],
           name: [temp_f: 0.5],
           name: [temp_f: 6.1],
           equipment: [cmd: "on"]
         ]
    test "handles :no_change case", ctx do
      assert %{sensor_group: sensor} = ctx
      assert %{equipment: %{name: equipment}} = ctx

      sensor = Rena.Sensor.tally(sensor, timezone: @tz)

      assert %Rena.Sensor{reading_at: %DateTime{}} = sensor

      chk_map = Rena.Sensor.next_action(equipment, sensor, return: :chk_map)
      assert %{next_action: next_action} = chk_map
      assert {:no_change, :none} = next_action
    end

    @tag sensor_group_add: [
           name: [temp_f: 0.1],
           name: [temp_f: 0.1],
           name: [temp_f: 0.5],
           name: [temp_f: 0.1],
           equipment: [cmd: "off"]
         ]
    test "handles :raise case", ctx do
      assert %{sensor_group: sensor} = ctx
      assert %{equipment: %{name: equipment}} = ctx

      sensor = Rena.Sensor.tally(sensor, timezone: @tz)

      assert %Rena.Sensor{reading_at: %DateTime{}} = sensor

      sensor = Rena.Sensor.next_action(equipment, sensor, return: :sensor)
      assert %Rena.Sensor{next_action: next_action} = sensor
      assert {:raise, "on"} = next_action
    end
  end
end
