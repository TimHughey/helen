defmodule GlowTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag glow: true, glow_base: true

  # NOTE: required tests are provided by Carol.AssertAid

  # describe "Glow instance execute args" do
  #   @tag skip: true
  #   test "validate front chandelier" do
  #     common_args = [equipment: "some name"]
  #     episodes = Glow.state(:chan, :episodes)
  #
  #     assert {[_ | _] = _args, [_ | _] = defaults} =
  #              execute = Carol.Episode.execute_args(common_args, :active, episodes)
  #
  #     if defaults[:cmd] == "Overnight" do
  #       args = Alfred.Execute.Args.auto(execute)
  #
  #       args |> tap(fn x -> ["\n", inspect(x, pretty: true)] |> IO.puts() end)
  #     end
  #   end
  # end
end
