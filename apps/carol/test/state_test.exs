defmodule Carol.StateTest do
  use ExUnit.Case, async: true

  @moduletag carol: true, carol_state: true

  describe "Carol.State.new/1" do
    test "assembles state from args" do
      start_args = Carol.Instance.start_args({:carol, Carol.Test, :front_chandelier})

      assert %Carol.State{} = Carol.State.new(start_args)
    end
  end

  describe "Carol.State.sched_opts/1" do
    test "returns full opts" do
      # NOTE: must create State to populate process dictionary
      start_args = Carol.Instance.start_args({:carol, Carol.Test, :front_chandelier})
      state = Carol.State.new(start_args)

      sched_opts = Carol.State.sched_opts(state)

      core = [:alfred, :server_name, :ttl_ms]
      event = [:latitude, :longitude, :ref_dt, :timezone]

      want_keys = (core ++ event) |> Enum.sort()
      got_keys = Enum.map(sched_opts, &elem(&1, 0)) |> Enum.sort()

      assert want_keys == got_keys
    end
  end
end
