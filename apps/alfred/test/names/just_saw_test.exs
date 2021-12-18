defmodule Alfred.JustSawTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag alfred: true, alfred_names: true, alfred_just_saw: true

  alias Alfred.JustSaw
  alias Alfred.SeenName
  alias Alfred.NamesAid

  defmacro assert_just_saw(res, mutable, seen_list, callback) do
    quote location: :keep do
      x = unquote(res)

      want_kv = [mutable?: unquote(mutable), callback: unquote(callback), valid?: true]

      Should.Be.Struct.with_all_key_value(x, JustSaw, want_kv)
      Should.Be.NonEmpty.list(unquote(seen_list))
    end
  end

  setup [:make_raw_seen_list]

  describe "Alfred.JustSaw.new/4" do
    @tag make_raw_seen_list: [count: 4]
    test "creates well formed immutable JustSaw", %{seen_list: seen_list} do
      callback = {:module, __MODULE__}

      res = JustSaw.new_immutable(seen_list, &map_raw/1, callback)

      assert_just_saw(res, false, seen_list, callback)
    end

    @tag make_raw_seen_list: [count: 4]
    test "creates well formed mutable JustSaw", %{seen_list: seen_list} do
      callback = {:module, __MODULE__}

      res = JustSaw.new_mutable(seen_list, &map_raw/1, callback)
      assert_just_saw(res, true, seen_list, callback)
    end
  end

  describe "Alfred.JustSaw.to_known_names/2" do
    test "returns [] when seen list is empty" do
      %JustSaw{seen_list: []}
      |> JustSaw.to_known_names()
      |> Should.Be.List.empty()
    end

    test "returns [] when JustSaw is invalid" do
      %JustSaw{valid?: false, seen_list: []}
      |> JustSaw.to_known_names()
      |> Should.Be.List.empty()
    end

    @tag make_raw_seen_list: [count: 10]
    test "returns list of KnownNames from valid JustSaw", %{seen_list: seen_list} do
      alias Alfred.KnownName

      callback = {:module, __MODULE__}
      js = JustSaw.new_immutable(seen_list, &map_raw/1, callback)

      known_names = JustSaw.to_known_names(js)

      Should.Be.List.with_length(known_names, 10)

      for kn <- known_names do
        Should.Be.Struct.with_all_key_value(kn, KnownName, callback: callback)
      end

      expected_names = for %SeenName{name: x, valid?: true} <- seen_list, do: x
      created_names = for %KnownName{name: x, valid?: true} <- known_names, do: x

      res = expected_names -- created_names
      Should.Be.List.empty(res)
    end

    @tag make_raw_seen_list: [count: 10]
    test "filters invalid SeenNames from valid JustSaw", %{seen_list: seen_list} do
      alias Alfred.KnownName

      callback = {:module, __MODULE__}
      js = JustSaw.new_immutable(seen_list, &map_raw/1, callback)
      js = %JustSaw{js | seen_list: [%SeenName{}] ++ js.seen_list}

      known_names = JustSaw.to_known_names(js)

      Should.Be.List.with_length(known_names, 10)

      for kn <- known_names do
        Should.Be.Struct.with_all_key_value(kn, KnownName, callback: callback)
      end

      expected_names = for %SeenName{name: x, valid?: true} <- seen_list, do: x
      created_names = for %KnownName{name: x, valid?: true} <- known_names, do: x

      res = expected_names -- created_names
      Should.Be.List.empty(res)
    end
  end

  describe "Alfred.JustSaw.validate/1" do
    test "accepts a function as the callback" do
      callback = fn x -> x end

      %JustSaw{callback: callback}
      |> JustSaw.validate()
      |> Should.Be.Struct.with_all_key_value(JustSaw, valid?: true)
    end

    test "detects invalid callback" do
      %JustSaw{seen_list: [%SeenName{}]}
      |> JustSaw.validate()
      |> Should.Be.Struct.with_all_key_value(JustSaw, valid?: false)
    end
  end

  def map_raw(raw), do: struct(SeenName, raw)

  def make_raw_seen_list(%{make_raw_seen_list: opts}) when is_list(opts) do
    count = opts[:count]
    ttl_ms = opts[:ttl_ms] || 15_000
    seen_at = opts[:seen_at] || DateTime.utc_now()

    seen_list =
      for _ <- 1..count do
        [name: NamesAid.unique("justsaw"), ttl_ms: ttl_ms, seen_at: seen_at]
      end

    %{seen_list: seen_list}
  end

  def make_raw_seen_list(ctx), do: ctx
end
