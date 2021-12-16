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

  describe "Glow.cmd_adjust_params/3" do
    test "finds program" do
      Glow.cmd_adjust_params("chan", "Overnight", max: 1024)
      |> Should.Be.ok()
    end
  end

  describe "Glow.cmd/1" do
    test "finds program" do
      Glow.cmd("chan", "Overnight")
      |> pretty_puts()
    end
  end

  describe "Glow.child_search/1" do
    test "finds one match" do
      Glow.child_search("chan")
      |> Should.Be.List.with_length(1)
      |> Should.Be.module()
    end
  end

  describe "Glow.put_child_list/1" do
    @tag skip: true
    test "outputs child list" do
      Glow.puts_child_list("HEADING")
    end
  end

  describe "Glow.state/0" do
    @tag skip: true
    test "prompts for a selection then gets state" do
      Glow.state()
    end
  end
end
