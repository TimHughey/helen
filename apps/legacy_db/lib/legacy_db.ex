defmodule LegacyDb do
  require Ecto.Query
  alias Ecto.Query

  alias LegacyDb.{PulseWidth, Repo, Sensor, Switch}

  def all_pwm_aliases do
    Repo.all(PulseWidth.Alias) |> Repo.preload(:device)
  end

  def all_switches do
    Repo.all(Switch.Device) |> Repo.preload(:aliases)
  end

  def all_switch_aliases do
    Repo.all(Switch.Alias) |> Repo.preload(:device)
  end
end
