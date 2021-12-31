defmodule FarmTest do
  use ExUnit.Case, async: true

  defmacro assert_started(server_name, opts) do
    quote bind_quoted: [server_name: server_name, opts: opts] do
      sleep = opts[:sleep] || 10
      attempts = opts[:attempts] || 1

      check = fn _ -> GenServer.whereis(server_name) |> is_pid() end

      for _ <- 1..attempts, reduce: :first do
        :first -> check.(:first)
        false -> Process.sleep(sleep) |> check.()
        true -> true
      end

      assert pid = GenServer.whereis(server_name)
      assert is_pid(pid)
    end
  end

  describe "Womb.Farm.Heater" do
    test "starts" do
      assert_started(Farm.Womb.Heater, attempts: 10)
    end
  end

  describe "Womb.Farm.Circulation" do
    test "starts" do
      assert_started(Farm.Womb.Circulation, attempts: 10)
    end
  end

  describe "Farm.womb_" do
    test "circulation_state/0 returns the State" do
      assert %Rena.HoldCmd.State{} = Farm.womb_circulation_state()
    end

    test "circulation_restart/0 restarts the server" do
      assert {:ok, pid} = Farm.womb_circulation_restart()
      assert is_pid(pid)
    end

    test "heater_state/0 returns the State" do
      assert %Rena.SetPt.State{} = Farm.womb_heater_state()
    end
  end
end
