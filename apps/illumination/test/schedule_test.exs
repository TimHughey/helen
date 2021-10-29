defmodule IlluminationScheduleTest do
  use ExUnit.Case, async: true
  use Should

  alias Illumination.Schedule
  alias Illumination.Schedule.Point
  alias Illumination.Schedule.Result

  @tz "America/New_York"

  setup ctx do
    ctx |> setup_create_manual_schedule()
  end

  test "Schedule.calc_point/2 handles overnight" do
    s = %Schedule{
      id: "overnight",
      start: %Point{sunref: "civil set"},
      finish: %Point{sunref: "civil rise"}
    }

    res = Schedule.calc_point(s, timezone: "America/New_York", datetime: Timex.now())

    should_be_struct(res, Schedule)
    assert Timex.day(res.start.at) < Timex.day(res.finish.at)
  end

  test "Schedule.calc_point/2 handles same day" do
    s = %Schedule{
      id: "same day",
      start: %Point{sunref: "civil rise"},
      finish: %Point{sunref: "civil set"}
    }

    res = Schedule.calc_point(s, timezone: "America/New_York", datetime: Timex.now())

    should_be_struct(res, Schedule)
    assert res.start.at.day == res.finish.at.day
  end

  @tag manual_schedule: [{18, 0}, {17, 0}, {1, 0}]
  test "Schedule.sort/1 works", %{schedule: unsorted} do
    sorted = Schedule.sort(unsorted)

    hours = for schedule <- sorted, do: schedule.start.at.hour

    assert hours == [1, 17, 18]
  end

  test "Schedule.calc_points/2 automatically recalculates past schedules" do
    schedules = [
      %Schedule{
        start: %Point{sunref: "sunrise"},
        finish: %Point{sunref: "sunrise", offset_ms: 60_000}
      },
      %Schedule{start: %Point{sunref: "noon"}, finish: %Point{sunref: "noon", offset_ms: 60_000}},
      %Schedule{
        start: %Point{sunref: "sunset"},
        finish: %Point{sunref: "sunset", offset_ms: 60_000}
      }
    ]

    dt = Timex.now(@tz)
    initial = Schedule.calc_points(schedules, datetime: dt, timezone: @tz)

    dt = Solar.event("sunrise", timezone: @tz) |> Timex.shift(milliseconds: 62_000)
    res = Schedule.find_active_and_next(initial, datetime: dt, timezone: @tz)

    should_be_non_empty_list(res)
    should_contain_key(res, :next)
    refute res[:active]

    dt = Solar.event("sunset", timezone: @tz)
    recalculated = Schedule.calc_points(initial, datetime: dt, timezone: @tz)
    res = Schedule.find_active_and_next(recalculated, datetime: dt, timzone: @tz)

    should_be_non_empty_list(res)
    should_contain_key(res, :active)
    should_contain_key(res, :next)

    should_be_equal(res[:next].start.sunref, "sunrise")
  end

  test "Schedule.find_active_and_next/2 finds schedules" do
    schedules = [
      %Schedule{
        start: %Point{sunref: "sunrise"},
        finish: %Point{sunref: "sunrise", offset_ms: 60_000}
      },
      %Schedule{start: %Point{sunref: "noon"}, finish: %Point{sunref: "noon", offset_ms: 60_000}},
      %Schedule{
        start: %Point{sunref: "sunset"},
        finish: %Point{sunref: "sunset", offset_ms: 60_000}
      },
      %Schedule{
        start: %Point{sunref: "end of day", offset_ms: -10_000},
        finish: %Point{sunref: "end of day"}
      }
    ]

    now = Timex.now(@tz)
    active_dt = Solar.event("sunset", timezone: @tz)

    schedules = Schedule.calc_points(schedules, timezone: @tz, datetime: now) |> Schedule.sort()

    res = Schedule.find_active_and_next(schedules, datetime: active_dt)

    should_be_non_empty_list(res)
    should_contain_key(res, :active)
    should_contain_key(res, :next)

    active = res[:active]

    should_be_struct(active, Schedule)
    should_be_equal(active.start.sunref, "sunset")

    next = res[:next]

    should_be_struct(next, Schedule)
    should_be_equal(next.start.sunref, "end of day")
  end

  test "Schedule.find_active_and_next/2 no active or next returns empty list" do
    schedules = [
      %Schedule{
        start: %Point{sunref: "sunrise"},
        finish: %Point{sunref: "sunrise", offset_ms: 60_000}
      },
      %Schedule{start: %Point{sunref: "noon"}, finish: %Point{sunref: "noon", offset_ms: 60_000}},
      %Schedule{
        start: %Point{sunref: "noon"},
        finish: %Point{sunref: "noon", offset_ms: 60_000}
      },
      %Schedule{
        start: %Point{sunref: "sunset", offset_ms: -10_000},
        finish: %Point{sunref: "sunset"}
      }
    ]

    now = Timex.now(@tz)
    active_dt = Solar.event("sunset", timezone: @tz) |> Timex.shift(minutes: 2)

    schedules = Schedule.calc_points(schedules, timezone: @tz, datetime: now) |> Schedule.sort()

    res = Schedule.find_active_and_next(schedules, datetime: active_dt)

    should_be_empty_list(res)
  end

  test "Schedule.effectuate/2 handles active and next schedule" do
    schedules = [
      %Schedule{
        id: "active",
        start: %Point{sunref: "sunrise", cmd: "on"},
        finish: %Point{sunref: "sunrise", offset_ms: 60_000}
      },
      %Schedule{
        id: "next",
        start: %Point{sunref: "sunset", cmd: "on"},
        finish: %Point{sunref: "sunset", offset_ms: 60_000}
      }
    ]

    opts = [alfred: AlfredSendExecMsg, equipment: "active_equipment"]
    active_dt = Solar.event("sunrise", timezone: @tz)

    schedules = Schedule.calc_points(schedules, opts ++ [datetime: active_dt])

    res =
      Schedule.find_active_and_next(schedules, opts ++ [datetime: active_dt])
      |> Schedule.effectuate(opts)

    should_be_struct(res, Result)
    should_be_struct(res.schedule, Schedule)
    should_be_equal(res.schedule.id, "active")
    should_be_struct(res.exec, Alfred.ExecResult)
    should_be_equal(res.action, :activated)

    receive do
      %Alfred.ExecCmd{name: "active_equipment", cmd: "on"} -> assert true
      error -> refute error
    after
      1000 -> assert false, "Alfred Exec Msg not recevied"
    end

    # test next (queuing of schedule)

    before_ms = 300_000
    next = Solar.event("sunset", timezone: @tz)
    between = Timex.shift(next, milliseconds: before_ms * -1)

    next_opts = [alfred: AlfredSendExecMsg, datetime: between, equipment: "queue_equipment"]

    res = Schedule.find_active_and_next(schedules, next_opts) |> Schedule.effectuate(next_opts)

    should_be_struct(res, Result)

    remaining_ms = Process.read_timer(res.queue_timer)

    should_be_struct(res.schedule, Schedule)
    should_be_equal(res.schedule.id, "next")
    should_be_equal(res.action, :queued)
    assert remaining_ms > before_ms - 10

    receive do
      %Alfred.ExecCmd{name: "queue_equipment", cmd: "off"} -> assert true
      error -> refute error
    after
      1000 -> assert false, "Alfred Exec Msg not recevied"
    end
  end

  test "Schedule.handle_cmd_ack/3 creates finish timer" do
    run_ms = 60_000
    start_at = Solar.event("sunset", timezone: @tz)
    finish_at = Solar.event("sunset", timezone: @tz) |> Timex.shift(milliseconds: run_ms)

    schedule = %Schedule{start: %Point{at: start_at}, finish: %Point{at: finish_at}}
    before_ms = 40
    acked_at = start_at |> Timex.shift(milliseconds: before_ms * -1)

    res = Schedule.handle_cmd_ack(schedule, acked_at, [])

    should_be_struct(res, Result)

    remaining_ms = Process.read_timer(res.run_timer)
    assert remaining_ms > run_ms - before_ms - 10
  end

  def setup_create_manual_schedule(%{manual_schedule: manual_schedule} = ctx) do
    ctx = put_in(ctx, [:schedule], [])
    dt = Timex.now("America/New_York")

    for {hour, min} <- manual_schedule, reduce: ctx do
      %{schedule: schedule} = acc ->
        entry = %Schedule{
          start: %Point{at: %DateTime{dt | hour: hour, minute: min}},
          finish: %Point{at: %DateTime{dt | hour: hour, minute: min}}
        }

        %{acc | schedule: schedule ++ [entry]}
    end
  end

  def setup_create_manual_schedule(ctx), do: ctx
end
