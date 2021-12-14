defmodule GlowTest do
  use ExUnit.Case
  use Should

  @moduletag glow: true, glow_base: true

  describe "Glow.children/0" do
    test "returns list of children" do
      children = Glow.children()

      Should.Be.List.with_length(children, 4)

      for {id, pid, _type, _module} <- children do
        Should.Be.module(id)
        Should.Be.pid(pid)
      end
    end
  end

  describe "Glow.put_child_list/1" do
    @tag skip: false
    test "outputs child list" do
      Glow.puts_child_list("HEADING")
    end
  end

  describe "Glow.state/0" do
    @tag skip: false
    test "prompts for a selection then gets state" do
      Glow.state()
    end
  end
end
