defmodule Rena.InitArgsAid do
  @moduledoc false

  @tz "America/New_York"

  def add(%{} = ctx) do
    case ctx do
      %{module: id, init_add: opts} ->
        init_args = add(opts ++ [id: id])
        {dev_alias, init_args} = Keyword.pop(init_args, :dev_alias)
        {sensor, init_args} = Keyword.pop(init_args, :sensor)

        %{init_args: init_args, dev_alias: dev_alias, sensor: sensor}

      _ ->
        :ok
    end
  end

  @add_steps [:equipment, :sensor_group, :name, :opts_generic]
  @want_created [:dev_alias, :equipment, :name, :opts, :sensor, :sensor_group]
  def add([_ | _] = opts) do
    opts_map = Enum.into(opts, %{timezone: @tz})

    Enum.reduce(@add_steps, opts_map, fn
      :equipment, opts_map -> equipment(opts_map)
      :sensor_group, opts_map -> sensor_group(opts_map)
      :name, opts_map -> name(opts_map)
      :server_name, %{id: id} = opts_map -> Map.put(opts_map, :server_name, id)
      :opts_generic, opts_map -> opts_generic(opts_map)
    end)
    |> Map.take(@want_created)
    |> Enum.into([])
  end

  def equipment(opts_map) do
    opts = Map.get(opts_map, :equipment, [])

    dev_alias = Alfred.NamesAid.new_dev_alias(:equipment, opts)

    Map.merge(opts_map, %{equipment: dev_alias.name, dev_alias: dev_alias})
  end

  def name(opts_map) do
    name = Alfred.NamesAid.unique("rena")

    Map.put(opts_map, :name, name)
  end

  def opts_generic(%{timezone: tz} = opts_map) do
    generic = [alfred: AlfredSim, echo: :tick, caller: self(), timezone: tz]
    put_in(opts_map, [:opts], generic)
  end

  def sensor_group(opts_map) do
    opts = Map.get(opts_map, :sensor_group, [])

    sensor = Rena.SensorGroupAid.add(opts)
    sensor_group_opts = Rena.SensorGroupAid.to_args(sensor)

    Map.merge(opts_map, %{sensor: sensor, sensor_group: sensor_group_opts})
  end
end
