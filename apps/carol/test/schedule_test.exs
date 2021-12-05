defmodule CarolScheduleTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag illumination: true, illumination_schedule: true

  alias Alfred.ExecCmd
  alias Carol.Schedule
  alias Carol.Schedule.Point
  alias Carol.Schedule.Result

  @tz "America/New_York"

  setup [:equipment_add, :schedule_add]

  describe "Carol.Schedule.calc_point/2" do
    test "handles overnight" do
      schedule =
        %Schedule{
          id: "overnight",
          start: %Point{sunref: "civil set"},
          finish: %Point{sunref: "civil rise"}
        }
        |> Schedule.calc_point(timezone: @tz, datetime: Timex.now())
        |> Should.Be.struct(Schedule)

      Should.Be.asserted(fn -> Timex.day(schedule.start.at) < Timex.day(schedule.finish.at) end)
    end

    test "handles same day" do
      schedule =
        %Schedule{
          id: "same day",
          start: %Point{sunref: "civil rise"},
          finish: %Point{sunref: "civil set"}
        }
        |> Schedule.calc_point(timezone: @tz, datetime: Timex.now())
        |> Should.Be.struct(Schedule)

      Should.Be.asserted(fn -> schedule.start.at.day == schedule.finish.at.day end)
    end

    @tag schedule_add: []
    test "automatically recalculates past schedules", ctx do
      opts = fn dt -> [datetime: dt, timezone: @tz] end

      schedules = ctx.schedules

      dt = Timex.now(@tz)

      initial = Schedule.calc_points(schedules, opts.(dt)) |> Should.Be.List.of_structs(Schedule)

      dt = Solar.event("sunrise", timezone: @tz) |> Timex.shift(milliseconds: 62_000)
      res = Schedule.find_active_and_next(initial, opts.(dt)) |> Should.Contain.keys([:next])

      refute res[:active], Should.msg(res, "should not contain key :active")

      dt = event_shifted("sunset", 0)
      recalculated = Schedule.calc_points(initial, opts.(dt)) |> Should.Be.List.of_structs(Schedule)
      res = Schedule.find_active_and_next(recalculated, opts.(dt)) |> Should.Contain.keys([:active, :next])

      Should.Be.asserted(fn -> res[:next].start.sunref == "sunrise" end)
    end
  end

  @tag schedule_add: [{18, 0}, {17, 0}, {1, 0}]
  test "Carol.Schedule.sort/1 works", %{schedule: unsorted} do
    sorted = Schedule.sort(unsorted)

    hours = for schedule <- sorted, do: schedule.start.at.hour

    assert hours == [1, 17, 18]
  end

  describe "Carol.Schedule.find_active_and_next/2" do
    @tag schedule_add: ["sunrise", "sunset", "end of day"]
    test "finds schedules", ctx do
      opts = fn dt -> [datetime: dt, timezone: @tz] end

      now = Timex.now(@tz)
      active_dt = event_shifted("sunset", 0)
      schedules = Schedule.calc_points(ctx.schedules, opts.(now)) |> Schedule.sort()

      schedules =
        Schedule.find_active_and_next(schedules, opts.(active_dt))
        |> Should.Contain.keys([:active, :next])

      Should.Be.struct(schedules[:active], Schedule)
      Should.Be.struct(schedules[:next], Schedule)

      Should.Be.equal(schedules[:active].start.sunref, "sunset")
      Should.Be.equal(schedules[:next].start.sunref, "end of day")
    end

    @tag schedule_add: []
    test "no active or next returns empty list", ctx do
      opts = fn dt -> [datetime: dt, timezone: @tz] end

      now = Timex.now(@tz)
      active_dt = event_shifted("sunset", 120 * 1000)
      # active_dt = Solar.event("sunset", timezone: @tz) |> Timex.shift(minutes: 2)

      schedules = Schedule.calc_points(ctx.schedules, opts.(now)) |> Schedule.sort()

      Schedule.find_active_and_next(schedules, opts.(active_dt)) |> Should.Be.List.with_length(0)
    end
  end

  describe "Carol.Schedule.effectuate/2" do
    @tag equipment_add: [cmd: "off"]
    @tag schedule_add: [
           {"active", "sunrise", %ExecCmd{cmd: "fade", cmd_params: %{type: "random"}}},
           {"next", "sunset", %ExecCmd{cmd: "on"}}
         ]
    test "handles active and next schedule", ctx do
      opts = [alfred: AlfredSim, equipment: ctx.equipment, cmd_opts: [echo: true]]

      active_dt = event_shifted("sunrise", 0)
      schedules = Schedule.calc_points(ctx.schedules, opts ++ [datetime: active_dt])

      res =
        Schedule.find_active_and_next(schedules, opts ++ [datetime: active_dt])
        |> Schedule.effectuate(opts)
        |> Should.Be.Struct.with_all_key_value(Result, action: :activated)

      Should.Be.Struct.with_all_key_value(res.schedule, Schedule, id: "active")

      Should.Be.struct(res.exec, Alfred.ExecResult)

      receive do
        {:echo, %ExecCmd{cmd: "fade", cmd_params: %{type: "random"}}} -> assert true
        error -> refute error, Should.msg(error, "should have received {:echo, %ExecCmd{}}")
      after
        1000 -> assert false, "Alfred Exec Msg not recevied"
      end

      # test next (queuing of schedule)

      before_ms = -300_000

      # create a datetime that is between active and next
      between = event_shifted("sunset", before_ms)

      # use the same opts from above with cmd_opts: [echo: true]
      cmd_inactive = %ExecCmd{name: ctx.equipment, cmd: "off"}
      next_opts = [cmd_inactive: cmd_inactive, datetime: between] ++ opts

      res =
        Schedule.find_active_and_next(schedules, next_opts)
        |> Schedule.effectuate(next_opts)
        |> Should.Be.Struct.with_all_key_value(Result, action: :queued)

      remaining_ms = Process.read_timer(res.queue_timer)

      Should.Be.Struct.with_all_key_value(res.schedule, Schedule, id: "next")

      Should.Be.asserted(fn -> remaining_ms > before_ms - 10 end)

      receive do
        {:echo, %ExecCmd{cmd: "off"}} -> assert true
        error -> refute error, Should.msg(error, "should have received {:echo, %ExecCmd{}}")
      after
        1000 -> assert false, "Alfred Exec Msg not recevied"
      end
    end
  end

  describe "Carol.Schedule.handle_cmd_ack/3" do
    test "creates finish timer" do
      run_ms = 60_000
      start_at = event_shifted("sunset", 0)
      finish_at = event_shifted("sunset", run_ms)

      schedule = %Schedule{start: %Point{at: start_at}, finish: %Point{at: finish_at}}
      before_ms = 40
      acked_at = event_shifted("sunset", before_ms * -1)

      res = Schedule.handle_cmd_ack(schedule, acked_at, []) |> Should.Be.struct(Result)

      remaining_ms = Process.read_timer(res.run_timer)
      assert remaining_ms > run_ms - before_ms - 10
    end
  end

  def equipment_add(ctx), do: Alfred.NamesAid.equipment_add(ctx)
  def schedule_add(ctx), do: Carol.ScheduleAid.add(ctx)

  defp event_shifted(sunref, shift_ms) do
    Solar.event(sunref, timezone: @tz)
    |> Timex.shift(milliseconds: shift_ms)
  end
end
