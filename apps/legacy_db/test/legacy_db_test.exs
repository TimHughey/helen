defmodule LegacyDbTest do
  use ExUnit.Case, async: true

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
    assert [%{} | _] = LegacyDb.all_pwm_aliases()
  end

  test "pwm all alias names" do
    assert [<<_::binary>> | _] = LegacyDb.all_pwm_names()
  end

  test "pwm lookup alias details" do
    assert %{name: _} = LegacyDb.pwm_alias("front leds porch")
  end

  test "sensor lookup alias details" do
    assert %{name: _} = LegacyDb.sensor_alias("display_tank")
  end

  test "switch lookup alias details" do
    assert %{name: _} = LegacyDb.switch_alias("display tank heater")
  end

  test "ds sensor lookup by device name" do
    assert %{name: "lab window west"} = LegacyDb.ds_sensor("ds.280cd73a1a1901")
  end
end
