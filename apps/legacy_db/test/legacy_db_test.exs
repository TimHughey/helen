defmodule LegacyDbTest do
  use ExUnit.Case, async: true
  use Should

  test "legacy db sensor" do
    import Ecto.Query, only: [from: 1]

    devs = from(s in LegacyDb.Sensor.Device) |> LegacyDb.Repo.all()

    assert is_list(devs)
    refute devs == []

    aliases = from(s in LegacyDb.Sensor.Alias) |> LegacyDb.Repo.all()

    assert is_list(aliases)
    refute aliases == []
  end

  test "legacy db switch devices" do
    import Ecto.Query, only: [from: 1]

    devs = from(s in LegacyDb.Switch.Device) |> LegacyDb.Repo.all()

    assert is_list(devs)
    refute devs == []

    aliases = from(s in LegacyDb.Switch.Alias) |> LegacyDb.Repo.all()

    assert is_list(aliases)
    refute aliases == []
  end

  test "legacy db pwm" do
    import Ecto.Query, only: [from: 1]

    devs = from(s in LegacyDb.PulseWidth.Device) |> LegacyDb.Repo.all()

    assert is_list(devs)
    refute devs == []

    aliases = from(s in LegacyDb.PulseWidth.Alias) |> LegacyDb.Repo.all()

    assert is_list(aliases)
    refute aliases == []
  end

  test "legacy db remotes" do
    import Ecto.Query, only: [from: 1]

    hosts = from(s in LegacyDb.Remote) |> LegacyDb.Repo.all()

    assert is_list(hosts)
    refute hosts == []

    profiles = from(p in LegacyDb.Remote.Profile) |> LegacyDb.Repo.all()

    assert is_list(profiles)
    refute profiles == []
  end

  test "pwm all aliases" do
    res = LegacyDb.all_pwm_aliases()
    should_be_non_empty_list(res)

    for pwm_alias <- res do
      should_be_struct(pwm_alias, LegacyDb.PulseWidth.Alias)
    end
  end

  test "pwm all alias names" do
    res = LegacyDb.all_pwm_names()
    should_be_non_empty_list(res)
  end

  test "pwm lookup alias details" do
    res = LegacyDb.pwm_alias("front leds porch")
    Should.Be.NonEmpty.map(res)
    should_contain_key(res, :name)
  end

  test "sensor lookup alias details" do
    res = LegacyDb.sensor_alias("display_tank")
    Should.Be.NonEmpty.map(res)
    should_contain_key(res, :host)
  end

  test "switch lookup alias details" do
    res = LegacyDb.switch_alias("display tank heater")
    Should.Be.NonEmpty.map(res)
    should_contain_key(res, :pio)
  end

  test "ds sensor lookup by device name" do
    res = LegacyDb.ds_sensor("ds.280cd73a1a1901")
    Should.Be.NonEmpty.map(res)
    should_contain_value(res, "lab window west")
  end
end
