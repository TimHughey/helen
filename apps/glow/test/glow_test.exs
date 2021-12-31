defmodule GlowTest do
  use ExUnit.Case

  @moduletag glow: true, glow_base: true

  describe "Glow.children/0" do
    test "returns list of children" do
      children = Glow.which_children()

      assert [{_, _, _, _} = _child1, _child2, _child3, _child4] = children

      for {id, pid, _type, _module} <- children do
        assert ["Glow" | _] = Module.split(id)
        assert is_pid(pid)
      end
    end
  end
end
