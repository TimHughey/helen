defmodule FarmTest do
  use ExUnit.Case, async: true
  use Carol.AssertAid, module: Farm

  defmacro assert_started(server_name, opts) do
    quote bind_quoted: [server_name: server_name, opts: opts] do
      sleep = opts[:sleep] || 10
      reductions = opts[:attempts] || 1

      assert Enum.reduce(1..reductions, :check, fn
               _x, :check -> GenServer.whereis(server_name)
               _x, pid when is_pid(pid) -> Process.alive?(pid)
               _x, false -> Process.sleep(sleep) && :check
               _x, true -> true
             end)

      assert GenServer.whereis(server_name)
    end
  end

  describe "Womb.Farm.Heater" do
    test "starts" do
      assert_started(Farm.Womb.Heater, attempts: 10)
    end
  end
end
