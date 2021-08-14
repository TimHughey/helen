defmodule Garden.Schedule do
  use Timex
  alias __MODULE__

  defstruct id: nil, description: nil, start_at: nil, finish_at: nil

  def active?(%Schedule{} = schedule, dt) do
    Timex.between?(dt, schedule.start_at, schedule.finish_at, inclusive: true)
  end

  def new(id, description, start, finish, location_opts) do
    %Schedule{
      id: id,
      description: description,
      start_at: start |> make_at(location_opts),
      finish_at: finish |> make_at(location_opts)
    }
  end

  defp make_at(%{sun_ref: sun_ref} = at_map, opts) do
    sun_ref = Solar.event(sun_ref, opts)
    plus = at_map[:plus] || Duration.zero()
    minus = (at_map[:minus] || Duration.zero()) |> Duration.invert()

    sun_ref |> Timex.add(plus) |> Timex.add(minus)
  end

  defp make_at(_at_map, _opts), do: nil
end

defmodule Garden.Ation do
  alias __MODULE__
  alias Garden.Schedule

  defstruct id: nil, cmd: nil, description: nil, equipment: nil, schedule: []

  def new(id, %{description: ation_desc, equipment: equipment} = ation_details, tod, location_opts) do
    %{description: schedule_desc, cmd: cmd, start: start, finish: finish} = ation_details[tod]

    %Ation{
      id: id,
      cmd: cmd,
      description: ation_desc,
      equipment: equipment,
      schedule: Schedule.new(tod, schedule_desc, start, finish, location_opts)
    }
  end
end

defmodule Garden.CmdDef do
  alias __MODULE__

  defstruct cmd: nil, params: %{}

  def new(cmd, params \\ %{}) when is_atom(cmd) do
    %CmdDef{cmd: Atom.to_string(cmd), params: params}
  end
end

defmodule Garden.Config do
  require Logger

  alias __MODULE__
  alias Garden.{Ation, CmdDef, Schedule}

  defstruct timezone: nil,
            latitude: nil,
            longitude: nil,
            cmds: %{on: CmdDef.new(:on), off: CmdDef.new(:off)},
            ations: %{},
            irrigation_power: nil,
            valid?: true,
            invalid_reason: ""

  def equipment(%Config{ations: ations}) do
    for({_key, %Ation{equipment: equipment}} <- ations, do: equipment) |> Enum.uniq()
  end

  def location_opts(%Config{timezone: tz, latitude: lat, longitude: long}) do
    [timezone: tz, latitude: lat, longitude: long]
  end

  def new({:ok, %{power: %{irrigation: irrigation_power}} = raw}) do
    %Config{irrigation_power: irrigation_power}
    |> handle_location(raw[:location])
    |> handle_cmds(raw[:cmd])
    |> handle_ation(:illumination, raw)
    |> handle_ation(:irrigation, raw)
  end

  def equipment_cmds(%Config{ations: ations} = cfg, %DateTime{} = now_dt) do
    equipment_cmds = for(name <- equipment(cfg), into: %{}, do: {name, %{type: nil, cmds: []}})

    for {{type, _ation_id, _tod}, %Ation{schedule: schedule, equipment: equipment} = ation} <- ations,
        reduce: equipment_cmds do
      acc ->
        entry = get_in(acc, [equipment])

        if Schedule.active?(schedule, now_dt) do
          %{acc | equipment => %{entry | type: type, cmds: [ation.cmd] ++ entry.cmds}}
        else
          %{acc | equipment => %{entry | type: type}}
        end
    end
  end

  defp handle_ation(%Config{} = cfg, type, map) do
    ations_map = map[type]
    loc_opts = location_opts(cfg)

    for {ation_id, ation_details} <- ations_map,
        {tod, _tod_details} <- ation_details,
        tod not in [:description, :equipment],
        reduce: cfg do
      %Config{ations: ations} ->
        key = {type, ation_id, tod}

        %Config{cfg | ations: put_in(ations, [key], Ation.new(ation_id, ation_details, tod, loc_opts))}
    end
  end

  defp handle_cmds(%Config{} = cfg, cmds) when is_map(cmds) do
    %Config{
      cfg
      | cmds:
          for {k, v} <- cmds, into: cfg.cmds do
            {k, CmdDef.new(k, v)}
          end
    }
  end

  defp handle_cmds(%Config{} = cfg, _), do: cfg

  defp handle_location(%Config{} = cfg, %{timezone: tz, latitude: lat, longitude: long}) do
    %Config{cfg | timezone: tz, latitude: lat, longitude: long}
  end

  defp handle_location(%Config{} = cfg, _) do
    %Config{cfg | valid?: false, invalid_reason: "timezone, latitude or longitude are missing"}
  end
end
