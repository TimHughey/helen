defmodule Carol.StateTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag carol: true, carol_state: true

  alias Carol.State

  describe "Carol.State.new/1" do
    test "assembles state from args" do
      Carol.Instance.start_args({:carol, CarolTest, :front_chandelier})
      |> State.new()
      |> Should.Be.struct(State)
    end
  end

  describe "Carol.State.sched_opts/0" do
    test "returns full opts" do
      # NOTE: must create State to populate process dictionary
      Carol.Instance.start_args({:carol, CarolTest, :front_chandelier}) |> State.new()

      want_keys = [:latitude, :longitude, :ref_dt, :server_name]

      State.sched_opts()
      |> Should.Be.List.with_keys(want_keys)
    end
  end
end
