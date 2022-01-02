defmodule SallyConfigTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_config: true

  describe "Sally.Config.dir_get/1" do
    test "returns :none when {mod, dir} unavailable" do
      assert :none == Sally.Config.dir_get({__MODULE__, :not_a_key})
    end

    test "returns binary when {mod, dir} are available" do
      profile_path = Sally.Config.dir_get({__MODULE__, :host_profiles})

      assert is_binary(profile_path)
      assert profile_path =~ ~r/profiles$/

      # confirm the discovered path was put into runtime
      profile_path = Sally.Config.Agent.runtime_get({__MODULE__, :host_profiles})

      assert is_binary(profile_path)
      assert profile_path =~ ~r/profiles$/
    end
  end
end
