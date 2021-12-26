defmodule SolarTest do
  use ExUnit.Case, async: true
  use Should

  describe "Solar.event/1" do
    test "success: can produce sunrise DateTime" do
      Solar.event("sunrise")
      |> Should.Be.datetime()
    end

    test "success: can produce sunset DateTime" do
      Solar.event("sunset")
      |> Should.Be.datetime()
    end

    test "success: can produce astro rise DateTime" do
      Solar.event("astro rise")
      |> Should.Be.datetime()
    end

    test "success: can produce astro set DateTime" do
      Solar.event("astro set")
      |> Should.Be.datetime()
    end

    test "success: can produce civil rise DateTime" do
      Solar.event("civil rise")
      |> Should.Be.datetime()
    end

    test "success: can produce civil set DateTime" do
      Solar.event("civil set")
      |> Should.Be.datetime()
    end

    test "success: can produce nautical rise DateTime" do
      Solar.event("nautical rise")
      |> Should.Be.datetime()
    end

    test "success: can produce nautical set DateTime" do
      Solar.event("nautical set")
      |> Should.Be.datetime()
    end

    test "success: can produce noon DateTime" do
      Solar.event("noon")
      |> Should.Be.datetime()
    end

    test "fail: can detect invalid type" do
      Solar.event("nautical unknown")
      |> Should.Be.Tuple.with_rc(:error)
    end

    test "fail: can detect invalid zenith" do
      Solar.event("bad zenith set")
    end

    test "success: can produce event for different date" do
      future_day = Timex.now("America/New_York") |> Timex.shift(days: 30)

      res = Solar.event("noon", datetime: future_day)

      assert future_day.day == res.day
    end
  end

  describe "Solar.event_opts/1" do
    test "returns a list of available binary events" do
      Solar.event_opts(:binaries)
      |> Should.Be.List.of_binaries()
    end
  end
end
