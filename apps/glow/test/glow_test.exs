defmodule GlowTest do
  use ExUnit.Case
  use Carol.AssertAid, module: Glow
  use Should

  @moduletag glow: true, glow_base: true

  # NOTE: required tests are provided by Carol.AssertAid

  describe "Glow instance execute args" do
    test "validate front chandelier" do
      common_args = [equipment: "some name"]
      episodes = Glow.state(:chan, :episodes)

      assert {[_ | _] = _args, [_ | _] = defaults} =
               execute = Carol.Episode.execute_args(common_args, :active, episodes)

      if defaults[:cmd] == "Overnight" do
        ec = Alfred.ExecCmd.Args.auto(execute) |> Alfred.ExecCmd.new()

        assert %Alfred.ExecCmd{
                 cmd: "off",
                 cmd_opts: [],
                 cmd_params: %{primes: _, step: _, step_ms: _},
                 name: "some name"
               } = ec
      end
    end
  end
end
