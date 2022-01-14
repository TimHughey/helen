defmodule Alfred.JustSawTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag alfred: true, alfred_just_saw: true

  defmacro assert_just_saw(new_js, want_kv) do
    quote location: :keep, bind_quoted: [new_js: new_js, want_kv: want_kv] do
      {callback, rest} = Keyword.pop(want_kv, :callback, :none)
      {mutable?, rest} = Keyword.pop(rest, :mutable?, false)
      {seen_list, _rest} = Keyword.pop(rest, :seen_list, [])

      # confirm in test params
      assert callback != :none
      assert is_boolean(mutable?)
      assert [_ | _] = seen_list

      # confirm the wanted seen list, convert to list of binaries and sort for assertion
      want_seen_names =
        Enum.map(seen_list, fn entry ->
          name = Keyword.get(entry, :name, :none)
          assert <<_::binary>> = name

          name
        end)
        |> Enum.sort()

      # confirm the newly created JustSaw and retrieve the seen list
      assert %Alfred.JustSaw{callback: ^callback, mutable?: ^mutable?, seen_list: new_seen_list} = new_js

      # confirm the newly created seen list, convert to binaries and sort for assertion
      new_seen_names =
        Enum.map(new_seen_list, fn seen_name ->
          assert %Alfred.SeenName{name: name, seen_at: %DateTime{}, ttl_ms: ttl_ms} = seen_name
          assert <<_::binary>> = name
          assert is_integer(ttl_ms)

          name
        end)
        |> Enum.sort()

      assert want_seen_names = new_seen_names
    end
  end

  setup [:make_raw_seen_list]

  describe "Alfred.JustSaw.new/4" do
    @tag make_raw_seen_list: [count: 4]
    test "creates well formed immutable JustSaw", ctx do
      want_kv = [callback: {:module, __MODULE__}, mutable?: false, seen_list: ctx.seen_list]

      Alfred.JustSaw.new_immutable(ctx.seen_list, &map_raw/1, {:module, __MODULE__})
      |> assert_just_saw(want_kv)
    end

    @tag make_raw_seen_list: [count: 4]
    test "creates well formed mutable JustSaw", ctx do
      want_kv = [callback: {:module, __MODULE__}, mutable?: true, seen_list: ctx.seen_list]

      Alfred.JustSaw.new_mutable(ctx.seen_list, &map_raw/1, {:module, __MODULE__})
      |> assert_just_saw(want_kv)
    end
  end

  describe "Alfred.JustSaw.to_known_names/2" do
    test "returns [] when seen list is empty" do
      known_names = %Alfred.JustSaw{seen_list: []} |> Alfred.JustSaw.to_known_names()
      assert [] = known_names
    end

    test "returns [] when JustSaw is invalid" do
      known_names = %Alfred.JustSaw{valid?: false, seen_list: []} |> Alfred.JustSaw.to_known_names()
      assert [] = known_names
    end

    @tag make_raw_seen_list: [count: 10]
    test "returns list of KnownNames from valid JustSaw", %{seen_list: seen_list} do
      callback = {:module, __MODULE__}
      js = Alfred.JustSaw.new_immutable(seen_list, &map_raw/1, callback)

      known_names = Alfred.JustSaw.to_known_names(js)
      assert [_ | _] = known_names
      assert length(known_names) == 10

      Enum.all?(known_names, fn kn -> assert %Alfred.KnownName{callback: ^callback} = kn end)

      # use for reduction here to filter invalid seen names
      expected_names = for %Alfred.SeenName{name: x, valid?: true} <- seen_list, do: x
      created_names = for %Alfred.KnownName{name: x, valid?: true} <- known_names, do: x

      assert [] = expected_names -- created_names
    end

    @tag make_raw_seen_list: [count: 10]
    test "filters invalid SeenNames from valid JustSaw", %{seen_list: seen_list} do
      callback = {:module, __MODULE__}
      js = Alfred.JustSaw.new_immutable(seen_list, &map_raw/1, callback)
      # NOTE: manually insert an invalid seen name
      js = struct(js, seen_list: [%Alfred.SeenName{} | js.seen_list])

      known_names = Alfred.JustSaw.to_known_names(js)
      assert [_ | _] = known_names
      assert length(known_names) == 10

      Enum.all?(known_names, fn kn -> assert %Alfred.KnownName{callback: ^callback} = kn end)

      # use for reduction here to filter invalid seen names
      expected_names = for %Alfred.SeenName{name: x, valid?: true} <- seen_list, do: x
      created_names = for %Alfred.KnownName{name: x, valid?: true} <- known_names, do: x

      assert [] = expected_names -- created_names
    end
  end

  describe "Alfred.JustSaw.validate/1" do
    test "accepts a function as the callback" do
      callback = fn x -> x end

      valid_js = %Alfred.JustSaw{callback: callback} |> Alfred.JustSaw.validate()
      assert %Alfred.JustSaw{valid?: true, callback: ^callback} = valid_js
    end

    test "detects invalid callback" do
      invalid_js = %Alfred.JustSaw{seen_list: [%Alfred.SeenName{}]} |> Alfred.JustSaw.validate()
      assert %Alfred.JustSaw{valid?: false} = invalid_js
    end
  end

  describe "Alfred.JustSaw.callbacks_defined/1" do
    test "returns accurate map for using module" do
      assert %{execute: {Alfred.JustSawImpl, 2}, status: {Alfred.JustSawImpl, 2}} =
               Alfred.JustSaw.callbacks(Alfred.JustSawImpl)
    end
  end

  describe "Alfred.DevAlias.just_saw/2" do
    test "processes a list of Alfred.DevAlias" do
      names =
        Enum.map(1..3, fn _x ->
          fake_ctx = %{sensor_add: [temp_f: 71.2]}
          %{sensor: name} = Alfred.NamesAid.sensor_add(fake_ctx)

          name
          |> Alfred.NamesAid.binary_to_parts()
          |> Alfred.Test.DevAlias.new()
        end)

      assert :ok = Alfred.Test.DevAlias.just_saw(names)

      assert %Alfred.Test.DevAlias{name: name} = List.first(names)
      assert %DateTime{} = Alfred.Name.seen_at(name)
    end
  end

  def map_raw(raw), do: struct(Alfred.SeenName, raw)

  def make_raw_seen_list(%{make_raw_seen_list: opts}) when is_list(opts) do
    count = opts[:count]
    ttl_ms = opts[:ttl_ms] || 15_000
    seen_at = opts[:seen_at] || DateTime.utc_now()

    base = [ttl_ms: ttl_ms, seen_at: seen_at]

    seen_list = Enum.map(1..count, fn _x -> Keyword.put(base, :name, Alfred.NamesAid.unique("justsaw")) end)

    %{seen_list: seen_list}
  end

  def make_raw_seen_list(ctx), do: ctx
end
