defmodule GlowTest do
  use ExUnit.Case
  use Should

  @moduletag glow: true, glow_base: true

  describe "Glow.child_search/1" do
    test "finds one match" do
      Glow.child_search("chan")
      |> Should.Be.List.with_length(1)
      |> Should.Be.module()
    end
  end

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
      |> Should.Be.NonEmpty.list()
    end
  end

  describe "Glow.instances" do
    test "returns a list of humanized instance names" do
      Glow.instances()
      |> Should.Be.NonEmpty.list()
    end
  end

  describe "Glow.opts/2" do
    test "handles :pause" do
      Glow.ops("ever", :pause)
      |> Should.Be.equal(:pause)
    end
  end

  describe "Glow.state/2" do
    test "retrieves playlist by default" do
      Glow.state("chan") |> Should.Be.List.of_tuples_with_size(2)
    end

    test "retrieves programs " do
      Glow.state("chan", :programs)
      |> Should.Be.List.of_structs(Carol.Program)
    end
  end
end
