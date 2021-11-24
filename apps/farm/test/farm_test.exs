defmodule FarmTest do
  use ExUnit.Case, async: true
  use Should

  test "womb starts" do
    for _ <- 1..100, reduce: false do
      false ->
        Process.sleep(10)
        GenServer.whereis(Farm.Womb) |> is_pid()

      true ->
        true
    end

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
