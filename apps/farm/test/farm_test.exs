defmodule FarmTest do
  use ExUnit.Case, async: true
  use Should

  defmacro should_start(server_name, opts) do
    quote location: :keep, bind_quoted: [server_name: server_name, opts: opts] do
      sleep = opts[:sleep] || 10
      attempts = opts[:attempts] || 1

      check = fn _ -> GenServer.whereis(server_name) |> is_pid() end

      for _ <- 1..attempts, reduce: :first do
        :first -> check.(:first)
        false -> Process.sleep(sleep) |> check.()
        true -> true
      end
      |> then(fn _ -> GenServer.whereis(server_name) |> Should.Be.pid() end)
    end
  end

  describe "Womb.Farm.Heater" do
    test "starts" do
      should_start(Farm.Womb.Heater, attempts: 10)
    end
  end

  describe "Womb.Farm.Circulation" do
    test "starts" do
      should_start(Farm.Womb.Circulation, attempts: 10)
    end
  end

  describe "Farm.womb_" do
    test "circulation_state/0 returns the State" do
      Farm.womb_circulation_state() |> Should.Be.struct(Rena.HoldCmd.State)
    end

    test "circulation_restart/0 restarts the server" do
      Farm.womb_circulation_restart() |> Should.Be.Ok.tuple_with_pid()
    end

    test "heater_state/0 returns the State" do
      Farm.womb_heater_state() |> Should.Be.struct(Rena.SetPt.State)
    end
  end
end
