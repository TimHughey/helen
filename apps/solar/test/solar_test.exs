defmodule SolarTest do
  use ExUnit.Case, async: true

  describe "Solar.event/1" do
    test "success: default opts produce datetime" do
      dt = Solar.Opts.new([]) |> Solar.event()

      assert %DateTime{} = dt
    end

    test "success: event set datetime" do
      dt = Solar.Opts.new(type: :set) |> Solar.event()

      assert %DateTime{} = dt
    end

    test "success: event rise datetime" do
      dt = Solar.Opts.new(type: :rise) |> Solar.event()

      assert %DateTime{} = dt
    end

    test "success: event civil zenith set datetime" do
      dt = Solar.Opts.new(type: :set, zenith: :civil) |> Solar.event()

      assert %DateTime{} = dt
    end

    test "fail: detect invalid type" do
      dt = Solar.Opts.new(type: :invalid) |> Solar.event()

      assert is_tuple(dt)
    end
  end
end
