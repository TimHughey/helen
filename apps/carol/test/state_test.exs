defmodule Carol.StateTest do
  use ExUnit.Case, async: true

  @moduletag carol: true, carol_state: true

  describe "Carol.State.new/1" do
    test "assembles state from args" do
      start_args = Carol.Instance.start_args({:carol, CarolTest, :front_chandelier})

      assert %Carol.State{} = Carol.State.new(start_args)
    end
  end

  describe "Carol.State.sched_opts/0" do
    test "returns full opts" do
      # NOTE: must create State to populate process dictionary
      start_args = Carol.Instance.start_args({:carol, CarolTest, :front_chandelier})
      _state = Carol.State.new(start_args)

      assert [{:alfred, _}, {:latitude, _}, {:longitude, _}, {:ref_dt, _}, {:server_name, _} | _] =
               Carol.State.sched_opts()
    end
  end
end
