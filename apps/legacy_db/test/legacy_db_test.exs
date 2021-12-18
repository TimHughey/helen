defmodule LegacyDbTest do
  use ExUnit.Case, async: true
  use Should

  @pwm_alias LegacyDb.PulseWidth.Alias
  @pwm_device LegacyDb.PulseWidth.Device
  @sensor_alias LegacyDb.Sensor.Alias
  @sensor_device LegacyDb.Sensor.Device
  @switch_alias LegacyDb.Switch.Alias
  @switch_device LegacyDb.Switch.Device

  test "legacy db sensor" do
    import Ecto.Query, only: [from: 1]

    devs = from(s in @sensor_device) |> LegacyDb.Repo.all()

    assert is_list(devs)
    refute devs == []

    aliases = from(s in @sensor_alias) |> LegacyDb.Repo.all()

    assert is_list(aliases)
    refute aliases == []
  end

  test "legacy db switch devices" do
    import Ecto.Query, only: [from: 1]

    devs = from(s in @switch_device) |> LegacyDb.Repo.all()

    assert is_list(devs)
    refute devs == []

    aliases = from(s in @switch_alias) |> LegacyDb.Repo.all()

    assert is_list(aliases)
    refute aliases == []
  end

  test "legacy db pwm" do
    import Ecto.Query, only: [from: 1]

    devs = from(s in @pwm_device) |> LegacyDb.Repo.all()

    assert is_list(devs)
    refute devs == []

    aliases = from(s in @pwm_alias) |> LegacyDb.Repo.all()

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
    LegacyDb.all_pwm_aliases()
    |> Should.Be.List.of_type(:map)
  end

  test "pwm all alias names" do
    LegacyDb.all_pwm_names()
    |> Should.Be.List.of_type(:binary)
  end

  test "pwm lookup alias details" do
    LegacyDb.pwm_alias("front leds porch")
    |> Should.Be.Map.with_key(:name)
  end

  test "sensor lookup alias details" do
    LegacyDb.sensor_alias("display_tank")
    |> Should.Be.Map.with_key(:name)
  end

  test "switch lookup alias details" do
    LegacyDb.switch_alias("display tank heater")
    |> Should.Be.Map.with_key(:name)
  end

  test "ds sensor lookup by device name" do
    LegacyDb.ds_sensor("ds.280cd73a1a1901")
    |> Should.Contain.value("lab window west")
  end
end
