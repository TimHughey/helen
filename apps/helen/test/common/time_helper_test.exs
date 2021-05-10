defmodule HelenTimeHelperTest do
  @moduledoc false

  alias Helen.Time.Helper

  use Timex
  use ExUnit.Case

  @moduletag :helen_time_helper

  setup_all do
    %{}
  end

  setup context do
    context
  end

  test "can convert various types to a duration" do
    # from ISO8601 binary
    secs17 = Helper.to_duration("PT17S")

    # from %Duration{}, unchanged
    assert %Duration{seconds: 17} = Helper.to_duration(secs17)

    # mins13secs1 = Helper.to_duration(minutes: 13, seconds: 1)
    # assert %Duration{seconds: 781} = mins13secs1

    # unhandled types are converted to zero
    from_atom = Helper.to_duration(:this_atom)
    assert Duration.zero() == from_atom
  end
end
