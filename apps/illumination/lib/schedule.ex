defmodule Illumination.Schedule.Point do
  alias __MODULE__

  defstruct sunref: nil, offset_ms: 0, at: nil, cmd: "off"

  @type t :: %Point{
          sunref: String.t(),
          offset_ms: integer(),
          at: DateTime.t(),
          cmd: String.t()
        }

  def calc_at(%Point{} = pt, opts \\ []) when is_list(opts) do
    tz = opts[:timezone]
    datetime = opts[:datetime]

    at = Solar.event(pt.sunref, datetime: datetime, timezone: tz)

    %Point{pt | at: Timex.shift(at, milliseconds: pt.offset_ms)}
  end
end

defmodule Illumination.Schedule.Result do
  alias __MODULE__
  alias Illumination.Schedule

  defstruct schedule: nil,
            exec: nil,
            queue_timer: nil,
            run_timer: nil,
            action: :none

  @type actions :: :activated | :queued | :live | :finished

  @type t :: %Result{
          schedule: Schedule.t(),
          exec: Alfred.ExecResult.t(),
          queue_timer: reference(),
          run_timer: reference(),
          action: actions()
        }
end

defmodule Illumination.Schedule do
  use Timex

  alias __MODULE__
  alias Alfred.ExecCmd
  alias Illumination.Schedule.{Point, Result}

  defstruct id: nil, start: %Point{}, finish: %Point{}

  @type t :: %Schedule{
          id: String.t(),
          start: Point.t(),
          finish: Point.t()
        }

  def activate(%Schedule{} = schedule, opts) do
    alfred = opts[:alfred] || Alfred
    cmds = opts[:cmds] || %{}

    cmd = schedule.start.cmd
    cmd_params = cmds[cmd] || %{}
    cmd_opts = [force: true, notify_when_released: true]

    ec = %ExecCmd{
      name: opts[:equipment],
      cmd: cmd,
      cmd_params: Enum.into(cmd_params, %{}),
      cmd_opts: cmd_opts
    }

    %Result{exec: alfred.execute(ec), schedule: schedule, action: :activated}

    # NOTE: see handle_cmd_ack/3 for logic that creates the finish timer
  end

  def calc_points([], _opts), do: []

  def calc_points([%Schedule{} | _] = schedules, opts) when is_list(opts) do
    datetime = opts[:datetime]

    for %Schedule{} = s <- schedules do
      cond do
        is_nil(s.start.at) ->
          calc_point(s, opts)

        Timex.after?(datetime, s.finish.at) ->
          opts = Keyword.replace(opts, :datetime, Timex.shift(datetime, days: 1))

          calc_point(s, opts)

        true ->
          s
      end
    end
    |> sort()
  end

  def calc_point(%Schedule{} = s, opts) when is_list(opts) do
    timezone = opts[:timezone]
    start_dt = opts[:datetime]
    finish_dt = if opts[:overnight], do: Timex.shift(start_dt, days: 1), else: start_dt

    start_pt = Point.calc_at(s.start, timezone: timezone, datetime: start_dt)
    finish_pt = Point.calc_at(s.finish, timezone: timezone, datetime: finish_dt)

    if Timex.before?(finish_pt.at, start_pt.at) do
      calc_point(s, opts ++ [overnight: true])
    else
      %Schedule{s | start: start_pt, finish: finish_pt}
    end
  end

  def effectuate([], _opts), do: %Result{}

  def effectuate(schedules, opts) when schedules != [] do
    active = schedules[:active]
    next = schedules[:next]

    case {active, next} do
      {%Schedule{} = x, _} -> activate(x, opts)
      {_, %Schedule{} = x} -> queue(x, opts)
    end
  end

  def ensure_non_negative(x) when x <= 0, do: 0
  def ensure_non_negative(x), do: x

  def find_active_and_next([], _opts), do: []

  def find_active_and_next([%Schedule{} | _] = schedules, opts) do
    dt = opts[:datetime]

    for s <- schedules, reduce: [] do
      acc ->
        cond do
          is_nil(s.start.at) or is_nil(s.finish.at) ->
            acc

          Timex.between?(dt, s.start.at, s.finish.at, inclusive: :start) ->
            Keyword.put_new(acc, :active, s)

          Timex.before?(dt, s.start.at) and Timex.before?(dt, s.finish.at) ->
            Keyword.put_new(acc, :next, s)

          true ->
            acc
        end
    end
  end

  def handle_cmd_ack(%Schedule{} = schedule, acked_at, opts) do
    ms = Timex.diff(schedule.finish.at, acked_at, :milliseconds)

    msg = {:finish, schedule, opts}
    ref = Process.send_after(self(), msg, ensure_non_negative(ms))
    %Result{schedule: schedule, action: :live, run_timer: ref}
  end

  def queue(%Schedule{} = schedule, opts) do
    alfred = opts[:alfred]
    datetime = opts[:datetime]
    equipment = opts[:equipment]

    # when a scheduled is queued ensure the equipment is off
    %ExecCmd{name: equipment, cmd: "off"} |> alfred.execute()

    ms = Timex.diff(schedule.start.at, datetime, :milliseconds)

    msg = {:activate, schedule, opts}
    ref = Process.send_after(self(), msg, ensure_non_negative(ms))

    %Result{schedule: schedule, action: :queued, queue_timer: ref}
  end

  def sort([%Schedule{} | _] = schedules) do
    Enum.sort(schedules, fn lhs, rhs -> Timex.compare(lhs.start.at, rhs.start.at) <= 0 end)
  end
end
