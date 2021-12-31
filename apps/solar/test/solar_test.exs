defmodule SolarTest do
  use ExUnit.Case, async: true

  describe "Solar.event/1" do
    test "success: can produce sunrise DateTime" do
      assert %DateTime{} = Solar.event("sunrise")
    end

    test "success: can produce sunset DateTime" do
      assert %DateTime{} = Solar.event("sunset")
    end

    test "success: can produce astro rise DateTime" do
      assert %DateTime{} = Solar.event("astro rise")
    end

    test "success: can produce astro set DateTime" do
      assert %DateTime{} = Solar.event("astro set")
    end

    test "success: can produce civil rise DateTime" do
      assert %DateTime{} = Solar.event("civil rise")
    end

    test "success: can produce civil set DateTime" do
      assert %DateTime{} = Solar.event("civil set")
    end

    test "success: can produce nautical rise DateTime" do
      assert %DateTime{} = Solar.event("nautical rise")
    end

    test "success: can produce nautical set DateTime" do
      assert %DateTime{} = Solar.event("nautical set")
    end

    test "success: can produce noon DateTime" do
      assert %DateTime{} = Solar.event("noon")
    end

    test "fail: can detect invalid type" do
      assert {:error, text} = Solar.event("nautical unknown")
      assert text =~ ~r/^type must include/
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
      assert [<<_::binary>> | _] = Solar.event_opts(:binaries)
    end
  end
end
