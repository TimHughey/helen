defmodule Janice.Jobs do
  @moduledoc false
  require Logger

  def flush do
    thermo = "grow heat"
    profile = "flush"

    if Thermostat.Server.profiles(thermo, active: true) === profile do
      true
    else
      Logger.info(fn -> "thermostat #{inspect(thermo)} set to #{inspect(profile)}" end)
      Thermostat.Server.activate_profile(thermo, profile)
    end
  end

  def germination(pos) when is_boolean(pos) do
    sw = "germination_light"
    curr = SwitchState.state(sw)

    if curr == pos do
      Logger.debug(fn -> "#{sw} position correct" end)
    else
      SwitchState.state(sw, position: pos, lazy: true)
      Logger.info(fn -> "#{sw} position set to #{inspect(pos)}" end)
    end
  end

  def grow do
    thermo = "grow heat"
    profile = "optimal"

    if Thermostat.Server.profiles(thermo, active: true) === profile do
      true
    else
      Logger.info(fn -> "thermostat #{inspect(thermo)} set to #{inspect(profile)}" end)
      Thermostat.Server.activate_profile(thermo, profile)
    end
  end

  def reefwater(:change) do
    dcs = [
      {"reefwater mix air", "off"},
      {"reefwater mix pump", "on"},
      {"display tank replenish", "off"},
      {"reefwater rodi fill", "off"}
    ]

    for {dc, p} <- dcs do
      Dutycycle.Server.activate_profile(dc, p, enable: true)
    end

    Thermostat.Server.activate_profile("reefwater mix heat", "match display tank")
  end

  def reefwater(:mix) do
    dcs = [
      {"reefwater mix air", "high"},
      {"reefwater mix pump", "high"},
      {"display tank replenish", "fast"},
      {"reefwater rodi fill", "off"}
    ]

    for {dc, p} <- dcs, do: Dutycycle.Server.activate_profile(dc, p, enable: true)

    Thermostat.Server.activate_profile("reefwater mix heat", "match display tank")
  end

  def reefwater(:fill_overnight) do
    dcs = [
      {"reefwater mix air", "off"},
      {"reefwater mix pump", "low"},
      {"display tank replenish", "slow"},
      {"reefwater rodi fill", "fast"}
    ]

    for {dc, p} <- dcs, do: Dutycycle.Server.activate_profile(dc, p, enable: true)

    Thermostat.Server.activate_profile("reefwater mix heat", "match display tank")
  end

  def reefwater(:low_energy) do
    dcs = [
      {"reefwater mix air", "low"},
      {"reefwater mix pump", "low"},
      {"display tank replenish", "fast"},
      {"reefwater rodi fill", "off"}
    ]

    for {dc, p} <- dcs, do: Dutycycle.Server.activate_profile(dc, p, enable: true)

    Thermostat.Server.activate_profile("reefwater mix heat", "low energy")
  end

  def touch_file do
    System.cmd("touch", ["/tmp/janice-every-minute"])
  end

  def touch_file(filename) when is_binary(filename) do
    System.cmd("touch", [filename])
  end
end
