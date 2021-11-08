defmodule FarmTest do
  use ExUnit.Case
  use Should

  test "womb starts" do
    pid = GenServer.whereis(Farm.Womb)

    should_be_pid(pid)
  end

  test "womb actions" do
    res = Farm.womb(:state)
    should_be_struct(res, Rena.SetPt.State)

    res = Farm.womb(:terminate)
    should_be_simple_ok(res)

    res = Farm.womb(:restart)
    should_be_ok_tuple_with_pid(res)
  end
end
