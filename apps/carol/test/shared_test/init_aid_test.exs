defmodule Carol.InitAid.Test do
  use ExUnit.Case, async: true
  use Carol.TestAid

  @moduletag carol: true, carol_init_aid: true

  describe "Carol.InitAid.add/1" do
    test "requires episodes option" do
      opts = [hello: :doctor]
      assert_raise(RuntimeError, ~r/episodes/, fn -> Carol.InitAid.add(opts) end)
    end

    test "creates init args" do
      opts = [episodes: {:short, [now: 1, future: 10, past: 12]}]
      init_args = Carol.InitAid.add(opts)

      want_keys = [:defaults, :dev_alias, :equipment, :episodes, :instance, :opts]
      assert Enum.all?(want_keys, &Keyword.get(init_args, &1))

      episodes = init_args[:episodes]

      assert Enum.count(episodes) == 23
      assert <<_::binary>> = init_args[:instance]

      assert [echo: :tick, caller: _, timezone: <<_::binary>>] = init_args[:opts]
    end

    test "create init args from ctx", ctx do
      opts = [episodes: {:short, [now: 1, future: 10, past: 12]}]

      assert %{init_args: _} = Map.put(ctx, :init_add, opts) |> Carol.InitAid.add()
    end
  end
end
