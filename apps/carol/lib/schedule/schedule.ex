defmodule Carol.Schedule do
  use Timex

  alias __MODULE__
  alias Alfred.ExecCmd
  alias Carol.Schedule.{Point, Result}

  defstruct id: nil, start: %Point{}, finish: %Point{}

  @type t :: %Schedule{
          id: String.t(),
          start: Point.t(),
          finish: Point.t()
        }

  @spec activate(Schedule.t(), opts :: list()) :: Result.t()
  def activate(%Schedule{} = schedule, opts) do
    {alfred, opts_rest} = Keyword.pop(opts, :alfred, Alfred)
    {equipment, opts_rest} = Keyword.pop(opts_rest, :equipment, "equipment missing")
    {cmd_opts, _} = Keyword.pop(opts_rest, :cmd_opts, [])

    ec = schedule.start.cmd

    final_ec = ExecCmd.add_name(ec, equipment) |> ExecCmd.merge_cmd_opts(cmd_opts)

    exec_result = alfred.execute(final_ec)

    %Result{exec: exec_result, schedule: schedule, action: :activated}

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
    {calc_opts, opts_rest} = Keyword.split(opts, [:timezone])
    {start_dt, opts_rest} = Keyword.pop(opts_rest, :datetime)
    {overnight?, _} = Keyword.pop(opts_rest, :overnight, false)

    finish_dt = if overnight?, do: Timex.shift(start_dt, days: 1), else: start_dt

    start_pt = Point.calc_at(s.start, [datetime: start_dt] ++ calc_opts)
    finish_pt = Point.calc_at(s.finish, [datetime: finish_dt] ++ calc_opts)

    if Timex.before?(finish_pt.at, start_pt.at) do
      calc_point(s, [overnight: true] ++ opts)
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
    {alfred, opts_rest} = Keyword.pop(opts, :alfred, Alfred)
    {datetime, opts_rest} = Keyword.pop(opts_rest, :datetime)
    {cmd_inactive, opts_rest} = Keyword.pop(opts_rest, :cmd_inactive)
    {cmd_opts, _} = Keyword.pop(opts_rest, :cmd_opts, [])

    # when a schedule is queued ensure the equipment is inactive
    cmd_inactive |> ExecCmd.merge_cmd_opts(cmd_opts) |> alfred.execute()

    ms = Timex.diff(schedule.start.at, datetime, :milliseconds)

    msg = {:activate, schedule, opts}
    ref = Process.send_after(self(), msg, ensure_non_negative(ms))

    %Result{schedule: schedule, action: :queued, queue_timer: ref}
  end

  def sort([%Schedule{} | _] = schedules) do
    Enum.sort(schedules, fn lhs, rhs -> Timex.compare(lhs.start.at, rhs.start.at) <= 0 end)
  end

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  defp ensure_non_negative(x) when x <= 0, do: 0
  defp ensure_non_negative(x), do: x
end
