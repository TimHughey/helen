defmodule SallyConfigAgentTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_config_agent: true

  describe "Sally.Config.Agent starts" do
    test "supervised" do
      start_args = [name: __MODULE__, test_key: true]
      assert {:ok, pid} = start_supervised({Sally.Config.Agent, start_args})
      assert Process.alive?(pid)

      assert %{config: %{test_key: true}, runtime: %{}} = :sys.get_state(start_args[:name])
    end

    test "via application" do
      assert pid = GenServer.whereis(Sally.Config.Agent)
      assert Process.alive?(pid)
    end
  end

  describe "Sally.Config.Agent.config_get/1" do
    @tag skip: true
    test "dump all" do
      :sys.get_state(Sally.Config.Agent) |> pretty_puts()
    end

    test "returns :none when {mod, key} do not exist" do
      assert :none == Sally.Config.Agent.config_get({:no_module, :unknown_key})
    end

    test "returns value of a known {mod, key}" do
      assert [hello: :doctor, yesterday: :tomorrow] = Sally.Config.Agent.config_get({__MODULE__, :key1})
    end
  end
end
