defmodule Alfred.JustSawTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag alfred: true, alfred_names: true, alfred_just_saw: true

  alias Alfred.JustSaw
  alias Alfred.SeenName
  alias Alfred.Test.Support

  defmacro should_be_just_saw(res, mutable, seen_list, callback) do
    quote location: :keep do
      x = unquote(res)
      should_be_struct(x, JustSaw)
      should_be_equal(x.mutable?, unquote(mutable))
      should_be_equal(x.callback, unquote(callback))
      should_be_equal(x.valid?, true)
      should_be_non_empty_list_with_length(x.seen_list, length(unquote(seen_list)))
    end
  end

  setup [:make_raw_seen_list]

  describe "Alfred.JustSaw.new/4" do
    @tag make_raw_seen_list: [count: 4]
    test "creates well formed immutable JustSaw", %{seen_list: seen_list} do
      callback = {:module, __MODULE__}

      res = JustSaw.new_immutable(seen_list, &map_raw/1, callback)

      should_be_just_saw(res, false, seen_list, callback)
    end

    @tag make_raw_seen_list: [count: 4]
    test "creates well formed mutable JustSaw", %{seen_list: seen_list} do
      callback = {:module, __MODULE__}

      res = JustSaw.new_mutable(seen_list, &map_raw/1, callback)
      should_be_just_saw(res, true, seen_list, callback)
    end
  end

  describe "Alfred.JustSaw.to_known_names/2" do
    test "returns [] when seen list is empty" do
      res = %JustSaw{seen_list: []} |> JustSaw.to_known_names()
      should_be_empty_list(res)
    end

    test "returns [] when JustSaw is invalid" do
      res = %JustSaw{valid?: false, seen_list: []} |> JustSaw.to_known_names()
      should_be_empty_list(res)
    end

    @tag make_raw_seen_list: [count: 10]
    test "returns list of KnownNames from valid JustSaw", %{seen_list: seen_list} do
      alias Alfred.KnownName

      callback = {:module, __MODULE__}
      js = JustSaw.new_immutable(seen_list, &map_raw/1, callback)

      known_names = JustSaw.to_known_names(js)

      should_be_non_empty_list_with_length(known_names, 10)

      for kn <- known_names do
        should_be_struct(kn, KnownName)
        should_be_equal(kn.callback, callback)
      end

      expected_names = for %SeenName{name: x, valid?: true} <- seen_list, do: x
      created_names = for %KnownName{name: x, valid?: true} <- known_names, do: x

      res = expected_names -- created_names
      should_be_empty_list(res)
    end

    @tag make_raw_seen_list: [count: 10]
    test "filters invalid SeenNames from valid JustSaw", %{seen_list: seen_list} do
      alias Alfred.KnownName

      callback = {:module, __MODULE__}
      js = JustSaw.new_immutable(seen_list, &map_raw/1, callback)
      js = %JustSaw{js | seen_list: [%SeenName{}] ++ js.seen_list}

      known_names = JustSaw.to_known_names(js)

      should_be_non_empty_list_with_length(known_names, 10)

      for kn <- known_names do
        should_be_struct(kn, KnownName)
        should_be_equal(kn.callback, callback)
      end

      expected_names = for %SeenName{name: x, valid?: true} <- seen_list, do: x
      created_names = for %KnownName{name: x, valid?: true} <- known_names, do: x

      res = expected_names -- created_names
      should_be_empty_list(res)
    end
  end

  describe "Alfred.JustSaw.validate/1" do
    test "accepts a function as the callback" do
      callback = fn x -> x end
      js = %JustSaw{callback: callback} |> JustSaw.validate()

      should_be_struct(js, JustSaw)
      should_be_equal(js.valid?, true)
    end

    test "detects invalid callback" do
      js = %JustSaw{seen_list: [%SeenName{}]} |> JustSaw.validate()

      should_be_struct(js, JustSaw)
      should_be_equal(js.valid?, false)
    end
  end

  def map_raw(raw), do: struct(SeenName, raw)

  def make_raw_seen_list(%{make_raw_seen_list: opts}) when is_list(opts) do
    count = opts[:count]
    ttl_ms = opts[:ttl_ms] || 15_000
    seen_at = opts[:seen_at] || DateTime.utc_now()

    seen_list =
      for _ <- 1..count do
        [name: Support.unique(:name), ttl_ms: ttl_ms, seen_at: seen_at]
      end

    %{seen_list: seen_list}
  end

  def make_raw_seen_list(ctx), do: ctx
end
