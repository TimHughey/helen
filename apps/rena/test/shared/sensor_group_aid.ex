defmodule Rena.SensorGroupAid do
  @moduledoc false

  def add(%{} = ctx) do
    case ctx do
      %{sensor_group_add: opts} -> add_for_ctx(opts)
      _ -> :ok
    end
  end

  @temp_f_defaults [11.0, 11.1, 11.2, 6.2]
  @names_default Enum.map(@temp_f_defaults, fn temp_f -> {:name, [rc: :ok, temp_f: temp_f]} end)
  def add(opts) when is_list(opts) do
    range = opts[:range] || [low: 1.0, high: 11.0, unit: :temp_f]

    {names_count, names} = names(opts)

    valid = if names_count == 1, do: 1, else: trunc(names_count / 2)

    adjust_when = Keyword.take(opts, [:adjust_when])
    valid_when = [valid: valid, total: names_count]
    fields = [names: names, range: range, valid_when: valid_when] ++ adjust_when

    Rena.Sensor.new(fields)
  end

  @steps [:equipment, :sensor_group]
  def add_for_ctx(opts) do
    equip_opts = Keyword.get(opts, :equipment, [])

    Enum.into(@steps, %{}, fn
      :equipment = key -> {key, Alfred.NamesAid.new_dev_alias(:equipment, equip_opts)}
      :sensor_group = key -> {key, add(opts)}
    end)
  end

  @want_fields [:names, :range, :valid_when, :adjust_when, :cmds]
  def to_args(%{} = sensor) do
    fields = Map.take(sensor, @want_fields)

    Enum.map(fields, fn {key, val} -> {key, Enum.into(val, [])} end)
  end

  def names(opts) do
    case Keyword.take(opts, [:name]) do
      [] -> @names_default
      [{:name, _opts} | _] = names -> names
      bad -> raise("invalid names: #{inspect(bad)}")
    end
    |> Enum.reduce({0, []}, fn {:name, opts}, {count, acc} ->
      dev_alias = Alfred.NamesAid.new_dev_alias(:sensor, opts)

      {count + 1, [dev_alias.name | acc]}
    end)
  end
end
