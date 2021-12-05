defmodule Illumination.ScheduleAid do
  alias Alfred.ExecCmd

  alias Illumination.Schedule
  alias Illumination.Schedule.Point

  @typical [
    {"early", "fixed 00:01:01", %ExecCmd{cmd: "on", cmd_opts: [echo: true]}},
    {"morning", "sunrise", %ExecCmd{cmd: "on", cmd_opts: [echo: true]}},
    {"midday", "noon", %ExecCmd{cmd: "fade", cmd_opts: [echo: true], cmd_params: [type: "random"]}},
    {"evening", "sunset", %ExecCmd{cmd: "fade2", cmd_opts: [echo: true], cmd_params: [type: "random"]}}
  ]

  # @live [
  #   {"morning", "sunrise", %ExecCmd{cmd: "on", cmd_opts: [echo: true]}},
  #   {"midday", "noon", %ExecCmd{cmd: "fade", cmd_opts: [echo: true], cmd_params: [type: "random"]}},
  #   {"evening", "sunset", %ExecCmd{cmd: "fade2", cmd_opts: [echo: true], cmd_params: [type: "random"]}}
  # ]

  # create schedules from {hour, minute} tuples
  def add(%{schedule_add: [{hour, minute} | _] = opts}) when is_integer(hour) and is_integer(minute) do
    for {hour, minute} <- opts do
      dt_ref = Timex.now("America/New_York")

      start_at = %DateTime{dt_ref | hour: hour, minute: minute}
      finish_at = start_at |> Timex.shift(minutes: 1)

      %Schedule{
        start: %Point{at: start_at},
        finish: %Point{at: finish_at}
      }
    end
    |> then(fn schedule -> %{schedule: schedule} end)
  end

  def add(%{schedule_add: [sunref | _] = opts}) when is_binary(sunref) do
    start_pt = %Point{sunref: "sunrise"}
    finish_pt = %Point{sunref: "sunrise", offset_ms: 60_000}

    for sunref <- opts do
      %Schedule{start: struct(start_pt, sunref: sunref), finish: struct(finish_pt, sunref: sunref)}
    end
    |> then(fn x -> %{schedules: x} end)
  end

  def add(%{schedule_add: [{id, sunref, %ExecCmd{}} | _] = opts}) when is_binary(id) and is_binary(sunref) do
    start_pt = %Point{sunref: "sunrise"}
    finish_pt = %Point{sunref: "sunrise", offset_ms: 60_000}

    for {id, sunref, cmd} <- opts do
      cmd = %ExecCmd{cmd | cmd_opts: [force: true, echo: true] ++ cmd.cmd_opts}

      %Schedule{
        id: id,
        start: struct(start_pt, sunref: sunref, cmd: cmd),
        finish: struct(finish_pt, sunref: sunref)
      }
    end
    |> then(fn x -> %{schedules: x} end)
  end

  # create a specific type of schedule
  def add(%{schedule_add: [opt]} = ctx) when is_atom(opt) do
    case opt do
      :typical -> Map.put(ctx, :schedule_add, @typical)
      _ -> Map.put(ctx, :schedule_add, [])
    end
    |> add()
  end

  def add(%{schedule_add: []}) do
    start_pt = %Point{sunref: "sunrise"}
    finish_pt = %Point{sunref: "sunrise", offset_ms: 60_000}

    [
      %Schedule{start: start_pt, finish: finish_pt},
      %Schedule{start: struct(start_pt, sunref: "noon"), finish: struct(finish_pt, sunref: "noon")},
      %Schedule{start: struct(start_pt, sunref: "sunset"), finish: struct(finish_pt, sunref: "sunset")}
    ]
    |> then(fn x -> %{schedules: x} end)
  end

  def add(_), do: :ok
end
