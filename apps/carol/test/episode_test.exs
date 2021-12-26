defmodule CarolEpisodeTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag carol: true, carol_episode: true

  @tz "America/New_York"

  setup [:opts_add, :episodes_add]

  defmacro assert_episodes(ctx, want_order) do
    quote bind_quoted: [ctx: ctx, want_order: want_order] do
      ctx
      #  |> episodes_summary()
      |> Should.Be.Map.with_key(:episodes)
      |> Should.Be.NonEmpty.list()
      |> Should.Be.List.of_type({:struct, Carol.Episode})

      new_episodes = Carol.Episode.analyze_episodes(ctx.episodes, ctx.opts)

      Should.Be.List.of_type(new_episodes, {:struct, Carol.Episode})

      # episodes_summary(new_episodes, ctx.ref_dt)

      if want_order != [] do
        Enum.map(new_episodes, fn e -> e.id end)
        |> Should.Be.equal(want_order)
      end

      new_episodes
    end
  end

  describe "Sally.Episode.new/1" do
    test "creates valid Episode with a Solar sun ref" do
      [event: "astro rise", calc: :later]
      |> Carol.Episode.new()
      |> Should.Be.Struct.of_key_types(Carol.Episode, event: :binary, at: :atom)
    end

    test "creates valid Episode from HH:MM:SS binary" do
      calc_opts = [timezone: @tz, ref_dt: Timex.now(@tz)]
      want_types = [event: :binary, at: :datetime]

      [event: "fixed 01:02:03"]
      |> Carol.Episode.new()
      |> Carol.Episode.calc_at(calc_opts)
      |> Should.Be.Struct.of_key_types(Carol.Episode, want_types)
    end
  end

  describe "Sally.Episode.analyze_episodes/2" do
    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    test "creates new episode list with active first, stale episodes refreshed", ctx do
      want_order = ["Now 1", "Future 1", "Future 2", "Future 3", "Past 3", "Past 2", "Past 1"]

      ctx
      |> assert_episodes(want_order)
      |> List.first()
      |> Should.Be.Struct.with_all_key_value(Carol.Episode, id: "Now 1")
    end

    @tag episodes_add: {:future, [count: 10, minutes: 1]}
    test "handles list of only future episides", ctx do
      want_order = ["Future 10"] ++ Enum.map(1..9, fn x -> "Future #{x}" end)

      ctx
      |> assert_episodes(want_order)
      |> Should.Be.List.with_length(10)
      |> List.first()
      |> Should.Be.Struct.with_all_key_value(Carol.Episode, id: "Future 10")
    end

    @tag episodes_add: {:past, [count: 10, minutes: 1]}
    test "handles list of only past episides", ctx do
      num_order = [1] ++ Enum.to_list(10..2)
      want_order = Enum.map(num_order, fn x -> "Past #{x}" end)

      ctx
      |> assert_episodes(want_order)
      |> Should.Be.List.with_length(10)
      |> List.first()
      |> Should.Be.Struct.with_all_key_value(Carol.Episode, id: "Past 1")
    end

    @tag episodes_add: {:single_future, []}
    test "handles single future episode", ctx do
      episodes = ctx |> assert_episodes(["Future 1"])

      # to be active the past episode is move to the past
      List.first(episodes).at
      |> Should.Be.DateTime.less(ctx.ref_dt)
    end

    @tag episodes_add: {:single_now, []}
    test "handles single now episode", ctx do
      episodes = ctx |> assert_episodes(["Now 1"])

      # to be active the past episode is move to the past
      List.first(episodes).at
      |> Should.Be.DateTime.compare_in(ctx.ref_dt, [:lt, :eq])
    end

    @tag episodes_add: {:single_past, []}
    test "handles single past episode", ctx do
      episodes = ctx |> assert_episodes(["Past 1"])

      # to be active the past episode is move to the past
      List.first(episodes).at
      |> Should.Be.DateTime.less(ctx.ref_dt)
    end

    test "handles empty list", ctx do
      Carol.Episode.analyze_episodes([], ctx.opts)
      |> Should.Be.List.empty()
    end
  end

  describe "Sally.Episode.ms_until_next_episode/2" do
    test "handles empty episode list", ctx do
      Carol.Episode.ms_until_next_episode([], ctx.opts)
      |> Should.Be.equal(1000)
    end

    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    test "handles mixed episode list", ctx do
      want_order = ["Now 1", "Future 1", "Future 2", "Future 3", "Past 3", "Past 2", "Past 1"]

      ctx
      |> assert_episodes(want_order)
      |> Carol.Episode.ms_until_next_episode(ctx.opts)
      |> Should.Be.equal(2000)
    end

    @tag episodes_add: {:future, [count: 10, minutes: 1]}
    test "handles list of only future episodes", ctx do
      want_order = ["Future 10"] ++ Enum.map(1..9, fn x -> "Future #{x}" end)

      assert_episodes(ctx, want_order)
      |> tap(fn [x | _] -> Should.Contain.kv_pairs(x, id: "Future 10") end)
      |> Carol.Episode.ms_until_next_episode(ctx.opts)
      |> Should.Be.equal(60_000)
    end
  end

  describe "Sally.Episode misc" do
    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    test "put_execute/2 updates :execute for the given id", ctx do
      episodes = ctx |> assert_episodes([])

      {"Future 2", [cmd: "updated", params: [type: "random"]]}
      |> Carol.Episode.put_execute(episodes)
      |> Enum.find(fn %{id: id} -> id == "Future 2" end)
      |> Should.Contain.key(:execute, :value)
      |> Should.Contain.kv_pairs(cmd: "updated")
    end

    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    test "execute_args/2 returns active execute args", ctx do
      episodes = ctx |> assert_episodes([])

      Carol.Episode.execute_args(:active, episodes)
      |> Should.Contain.key(:cmd)
    end

    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    test "execute_args/2 returns execute args for known id", ctx do
      episodes = ctx |> assert_episodes([])

      Carol.Episode.execute_args("Past 3", episodes)
      |> Should.Contain.key(:cmd)
    end

    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    test "execute_args/2 returns empty list for unknown id", ctx do
      episodes = ctx |> assert_episodes([])

      Carol.Episode.execute_args("Unknown", episodes)
      |> Should.Be.List.empty()
    end
  end

  describe "Sally.Episode.status_from_list/2" do
    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    test "creates list of status maps", ctx do
      episodes = assert_episodes(ctx, [])

      Carol.Episode.status_from_list(episodes, ctx.opts ++ [format: :humanized])
      |> Should.Be.List.of_binaries()
    end
  end

  def episodes_summary(%{episodes: episodes, ref_dt: ref_dt} = ctx) do
    episodes_summary(episodes, ref_dt)

    ctx
  end

  def episodes_summary(episodes, ref_dt) do
    for e <- episodes do
      #  diff = Timex.diff(ref_dt, e.at, :duration) |> Timex.format_duration(:humanized)

      diff = Timex.diff(e.at, ref_dt, :milliseconds)

      {e.id, diff}
    end
    |> pretty_puts()

    episodes
  end

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  defp episodes_add(ctx), do: Carol.EpisodeAid.add(ctx)
  defp opts_add(ctx), do: Carol.OptsAid.add(ctx)
end
