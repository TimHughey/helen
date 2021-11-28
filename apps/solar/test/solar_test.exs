defmodule SolarTest do
  use ExUnit.Case, async: true
  use Should

  describe "Solar.event/1" do
    test "success: can produce sunrise DateTime" do
      res = Solar.event("sunrise")
      Should.Be.struct(res, DateTime)
    end

    test "success: can produce sunset DateTime" do
      res = Solar.event("sunset")
      Should.Be.struct(res, DateTime)
    end

    test "success: can produce astro rise DateTime" do
      res = Solar.event("astro rise")
      Should.Be.struct(res, DateTime)
    end

    test "success: can produce astro set DateTime" do
      res = Solar.event("astro set")
      Should.Be.struct(res, DateTime)
    end

    test "success: can produce civil rise DateTime" do
      res = Solar.event("civil rise")
      Should.Be.struct(res, DateTime)
    end

    test "success: can produce civil set DateTime" do
      res = Solar.event("civil set")
      Should.Be.struct(res, DateTime)
    end

    test "success: can produce nautical rise DateTime" do
      res = Solar.event("nautical rise")
      Should.Be.struct(res, DateTime)
    end

    test "success: can produce nautical set DateTime" do
      res = Solar.event("nautical set")
      Should.Be.struct(res, DateTime)
    end

    test "success: can produce noon DateTime" do
      res = Solar.event("noon")
      Should.Be.struct(res, DateTime)
    end

    test "fail: can detect invalid type" do
      res = Solar.event("nautical unknown")
      should_be_tuple_with_rc(res, :error)
    end

    test "fail: can detect invalid zenith" do
      res = Solar.event("bad zenith set")
      should_be_tuple_with_rc(res, :error)
    end

    test "success: can produce event for different date" do
      future_day = Timex.now("America/New_York") |> Timex.shift(days: 30)

      res = Solar.event("noon", datetime: future_day)

      assert future_day.day == res.day
    end

    # test "success: event set datetime" do
    #   dt = Solar.Opts.new(type: :set) |> Solar.event()
    #
    #   assert %DateTime{} = dt
    # end
    #
    # test "success: event rise datetime" do
    #   dt = Solar.Opts.new(type: :rise) |> Solar.event()
    #
    #   assert %DateTime{} = dt
    # end
    #
    # test "success: event civil zenith set datetime" do
    #   dt = Solar.Opts.new(type: :set, zenith: :civil) |> Solar.event()
    #
    #   assert %DateTime{} = dt
    # end
    #
    # test "fail: detect invalid type" do
    #   dt = Solar.Opts.new(type: :invalid) |> Solar.event()
    #
    #   assert is_tuple(dt)
    # end
  end
end
