defmodule AlfredTest do
  use ExUnit.Case
  use Should

  setup_all ctx do
    ctx
  end

  describe "Alfred Names" do
    setup(:create_mutables)

    test "success: can get known names", %{names: names} do
      created_names_count = Enum.count(names)
      known_names = Alfred.known_names()

      should_be_non_empty_list(known_names)
      assert Enum.count(known_names) >= created_names_count, "should be >= #{created_names_count}"
    end

    test "success: can lookup a known name", _ctx do
      kn = Alfred.Names.lookup("mutable0")

      should_be_struct(kn, Alfred.KnownName)
      assert kn.name == "mutable0", "should find KnownName for 'mutable0' : #{inspect(kn, pretty: true)}"
    end

    test "success: can delete a known name", _ctx do
      kn = Alfred.delete("mutable9")

      should_be_struct(kn, Alfred.KnownName)
      assert kn.name == "mutable9", "should delete KnownName for 'mutable9' : #{inspect(kn, pretty: true)}"
    end

    test "success: can detect a name is known", _ctx do
      msg = "should know name 'mutable1'"
      assert Alfred.is_name_known?("mutable1"), msg
    end

    test "success: can detect a name is unknown", _ctx do
      name = "Unknown Name"
      msg = "should not know name '#{name}'"
      assert Alfred.Names.lookup(name) |> Alfred.KnownName.unknown?(), msg
    end

    test "success: can determine a name is available", _ctx do
      rc = Alfred.available?("mutable10")

      assert rc == true, "should return true: #{rc}"
    end

    @tag name: "missing"
    @tag ttl_ms: 1
    test "success: can detect a missing KnownName", ctx do
      created = Alfred.JustSaw.new(Alfred.Test.CallbackMod, true, ctx) |> Alfred.just_saw()

      should_be_non_empty_list(created)

      assert created == [ctx.name],
             "Alfred.just_saw/1 should return seen name: #{inspect(created, pretty: true)}"

      Process.sleep(10)

      kn = Alfred.Names.lookup(ctx.name)
      assert kn |> Alfred.KnownName.missing?(), "#{ctx.name} should be missing"
    end
  end

  def create_mutables(ctx) do
    alias Alfred.JustSaw

    names =
      for num <- 0..9 do
        name = "mutable#{num}"
        mutable = JustSaw.new(Alfred.Test.CallbackMod, true, %{name: name, ttl_ms: 10_000})
        rc = Alfred.just_saw(mutable)

        should_be_non_empty_list(rc)
        assert rc == [name], "Alfred.just_saw/1 should return seen name: #{inspect(rc, pretty: true)}"

        Alfred.just_saw_cast(mutable)
      end
      |> List.flatten()

    put_in(ctx, [:names], names)
  end

  def create_name(%{type: type} = ctx) do
    created = Alfred.JustSaw.new(Alfred.Test.CallbackMod, type, ctx) |> Alfred.just_saw()

    should_be_non_empty_list(created)

    msg = "Alfred.just_saw/1 should return seen name: #{inspect(created, pretty: true)}"
    assert created == [ctx.name], msg

    ctx
  end
end
