defmodule LegacyDbTest do
  use ExUnit.Case, async: true

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
end
