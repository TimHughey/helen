defmodule LegacyDb do
  require Ecto.Query
  alias Ecto.Query

  alias LegacyDb.{PulseWidth, Repo, Sensor, Switch}

  def all_pwm_aliases do
    Repo.all(PulseWidth.Alias) |> Repo.preload(:device)
  end

  def all_pwm_names, do: all_alias_names(PulseWidth.Alias)

  def all_sensors do
    Repo.all(Sensor.Alias) |> Repo.preload(:device)
  end

  def all_sensor_names, do: all_alias_names(Sensor.Alias)

  def all_switches do
    Repo.all(Switch.Device) |> Repo.preload(:aliases)
  end

  def all_switch_aliases do
    Repo.all(Switch.Alias) |> Repo.preload(:device)
  end

  def all_switch_names, do: all_alias_names(Switch.Alias)

  def pwm_alias(name) do
    alias PulseWidth.Alias, as: Schema

    query = Query.from(x in Schema, where: x.name == ^name)

    case Repo.one(query) |> Repo.preload(:device) do
      %Schema{} = x -> make_alias_details(x)
      failure -> failure
    end
  end

  def sensor_alias(name) do
    alias Sensor.Alias, as: Schema

    query = Query.from(x in Schema, where: x.name == ^name)

    case Repo.one(query) |> Repo.preload(:device) do
      %Schema{} = x -> make_alias_details(x)
      failure -> failure
    end
  end

  def switch_alias(name) do
    alias Switch.Alias, as: Schema

    query = Query.from(x in Schema, where: x.name == ^name)

    case Repo.one(query) |> Repo.preload(:device) do
      %Schema{} = x -> make_alias_details(x)
      failure -> failure
    end
  end

  defp all_alias_names(schema) do
    Query.from(x in schema, select: [x.name]) |> Repo.all()
  end

  defp make_alias_details(alias_schema) do
    alias_details = Map.take(alias_schema, [:description, :pio, :ttl_ms, :name])
    dev_details = Map.take(alias_schema.device, [:device, :host, :last_seen_at, :last_cmd_at])

    for {key, val} <- dev_details do
      case key do
        k when k in [:last_seen_at, :last_cmd_at] -> {k, Timex.to_datetime(val, "America/New_York")}
        k -> {k, val}
      end
    end
    |> Enum.into(alias_details)
  end
end
