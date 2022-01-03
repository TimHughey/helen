defmodule GlowTest do
  use ExUnit.Case
  use Carol.AssertAid, module: Glow
  use Should

  @moduletag glow: true, glow_base: true

  # NOTE: required tests are provided by Carol.AssertAid

  describe "Glow instance execute args" do
    test "validate front chandelier" do
      episodes = Glow.state(:chan, :episodes)

      ec =
        Carol.Episode.execute_args([equipment: "some name"], :active, episodes)
        |> Alfred.ExecCmd.Args.auto()
        |> Alfred.ExecCmd.new()

      assert %Alfred.ExecCmd{
               cmd: "Overnight",
               cmd_opts: [],
               cmd_params: %{min: _, max: _, primes: _, step: _, step_ms: _, type: "random"},
               name: "some name"
             } = ec
    end
  end
end
