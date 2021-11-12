defmodule Alfred.JustSawTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag alfred: true, alfred_names: true, alfred_just_saw_test: true

  alias Alfred.JustSaw
  alias Alfred.JustSaw.Alias

  describe "Alfred.JustSaw.DevAlias.new/1" do
    test "handles nil" do
      res = Alias.new(nil)

      should_be_non_empty_list_with_length(res, 1)
      first = hd(res)
      should_be_struct(first, Alias)
      should_be_equal(first.valid?, false)
    end

    test "handles creating a single DevAlias" do
      res = Alias.new(name: "test", ttl_ms: 99)

      should_be_non_empty_list_with_length(res, 1)
      first = hd(res)

      should_be_match(first, %Alias{name: "test", ttl_ms: 99, valid?: true})
    end

    test "handles creating a list of DevAlias" do
      da1 = [name: "test1", ttl_ms: 99]
      da2 = %{name: "test2", ttl_ms: 100}
      da3 = [name: "test3", ttl_ms: 101]

      res = Alias.new([da1, da2, da3])
      should_be_non_empty_list_with_length(res, 3)
    end

    test "handles incomplete args and detects invalid" do
      res = Alias.new(name: "test")

      should_be_non_empty_list_with_length(res, 1)
      first = hd(res)
      should_be_struct(first, Alias)
      should_be_equal(first.valid?, false)
    end
  end

  describe "Alfred.JustSaw.new/1" do
    test "handles missing and incomplete args" do
      res = JustSaw.new([])

      should_be_struct(res, JustSaw)
      should_be_equal(res.valid?, false)
      should_be_non_empty_list_with_length(res.seen_list, 1)
    end

    test "handles complete args and sets valid?" do
      seen = [[name: "test1", ttl_ms: 99], %{name: "test2", ttl_ms: 100}]
      args = [callback_mod: __MODULE__, mutable?: true, seen: seen]
      res = JustSaw.new(args)

      should_be_struct(res, JustSaw)
      should_be_equal(res.valid?, true)
      should_be_equal(res.callback_mod, args[:callback_mod])
      should_be_equal(res.mutable?, args[:mutable?])
      should_be_non_empty_list_with_length(res.seen_list, 2)
    end
  end
end
