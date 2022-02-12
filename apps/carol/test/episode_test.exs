defmodule CarolEpisodeTest do
  use ExUnit.Case, async: true

  @moduletag carol: true, carol_episode: true

  @tz "America/New_York"

  setup [:opts_add, :episodes_add, :episodes_summary]

  defmacro msg(lhs, text, rhs) do
    quote bind_quoted: [lhs: lhs, text: text, rhs: rhs] do
      [Macro.to_string(lhs), text, Macro.to_string(rhs), "\n"]
      |> Enum.join("\n")
    end
  end

  @fail_msgs [
    active: "active should be less than or equal to ref_dt",
    rest: "episode should be greater than previous"
  ]
  defmacro assert_active(episodes, ref_dt) do
    quote bind_quoted: [episodes: episodes, ref_dt: ref_dt] do
      active = hd(episodes)

      assert Timex.compare(active.at, ref_dt) <= 0, msg(active, @fail_msgs[:active], ref_dt)
    end
  end

  defmacro assert_episodes(ctx) do
    quote bind_quoted: [ctx: ctx] do
      episode_count = episode_count(ctx)

      episodes = ctx.episodes
      assert [%Carol.Episode{} | _] = episodes
      assert length(episodes) == episode_count

      case episode_count do
        x when x >= 2 ->
          assert_active(episodes, ctx.ref_dt)
          assert_rest(episodes, ctx.ref_dt)

        x when x == 1 ->
          assert_active(episodes, ctx.ref_dt)

        # empty episode list
        _ ->
          assert true
      end

      episodes
    end
  end

  defmacro assert_rest(episodes, ref_dt) do
    quote bind_quoted: [episodes: episodes, ref_dt: ref_dt] do
      [active | rest] = episodes

      Enum.reduce(rest, active, fn episode, previous ->
        assert Timex.compare(episode.at, previous.at) >= 0, msg(episode, @fail_msgs[:rest], previous)
        # accumulate the single previous
        previous
      end)
    end
  end

  @add_keys [:future, :now, :past, :yesterday]
  defp episode_count(ctx) when is_map(ctx) do
    add_opts = ctx[:episodes_add] || :none

    case add_opts do
      :none -> 0
      {_, []} -> 1
      {_, [_ | _] = x} -> episode_count(x)
    end
  end

  defp episode_count(add_opts) when is_list(add_opts) do
    Enum.reduce(add_opts, 0, fn
      {k, v}, acc when k in @add_keys -> acc + v
      {:count, v}, _acc -> v
      _kv, acc -> acc
    end)
  end

  describe "Sally.Episode.new/1" do
    test "creates valid Episode with a Solar sun ref" do
      assert %Carol.Episode{event: <<_::binary>>, at: :none} = Carol.Episode.new(event: "astro rise")
    end

    test "creates valid Episode from HH:MM:SS binary" do
      calc_opts = [timezone: @tz, ref_dt: Timex.now(@tz)]

      assert %Carol.Episode{event: <<_::binary>>, at: %DateTime{}} =
               Carol.Episode.new(event: "fixed 01:02:03") |> Carol.Episode.calc_at(calc_opts)
    end
  end

  describe "Sally.Episode.analyze_episodes/2" do
    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    test "handle list of past, now and future episodes", ctx do
      assert_episodes(ctx)
    end

    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3, yesterday: 1]}
    test "handle list of past, now, yesterday and future episodes", ctx do
      assert_episodes(ctx)
    end

    @tag episodes_add: {:future, [count: 10, minutes: 1]}
    test "handles list of only future episides", ctx do
      assert_episodes(ctx)
    end

    @tag episodes_add: {:past, [count: 10, minutes: 1]}
    test "handles list of only past episides", ctx do
      assert_episodes(ctx)
    end

    @tag episodes_add: {:single_future, []}
    test "handles single future episode", ctx do
      assert_episodes(ctx)
    end

    @tag episodes_add: {:single_now, []}
    test "handles single now episode", ctx do
      assert_episodes(ctx)
    end

    @tag episodes_add: {:single_past, []}
    test "handles single past episode", ctx do
      assert_episodes(ctx)
    end

    test "handles empty list", ctx do
      assert [] = Carol.Episode.analyze_episodes([], ctx.opts)
    end
  end

  describe "Sally.Episode.ms_until_next_episode/2" do
    test "handles empty episode list", ctx do
      assert 1000 = Carol.Episode.ms_until_next_episode([], ctx.opts)
    end

    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    test "handles mixed episode list", ctx do
      episodes = assert_episodes(ctx)

      assert 6000 = Carol.Episode.ms_until_next_episode(episodes, ctx.opts)
    end

    @tag episodes_add: {:future, [count: 10, minutes: 1]}
    test "handles list of only future episodes", ctx do
      episodes = assert_episodes(ctx)

      assert 63_000 = Carol.Episode.ms_until_next_episode(episodes, ctx.opts)
    end

    @tag episodes_add: {:whole_day, []}
    test "handles a single episode for the whole day", ctx do
      episodes = assert_episodes(ctx)

      next_ms = Carol.Episode.ms_until_next_episode(episodes, ctx.opts)

      assert next_ms >= 0
    end
  end

  describe "Sally.Episode misc" do
    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    test "put_execute/2 updates :execute for the given id", ctx do
      episodes = assert_episodes(ctx)

      episodes =
        {"Future 2", [cmd: "updated", params: [type: "random"]]}
        |> Carol.Episode.put_execute(episodes)

      assert %Carol.Episode{execute: [{:cmd, "updated"} | _]} =
               Enum.find(episodes, fn %{id: id} -> id == "Future 2" end)
    end

    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    test "execute_args/2 returns active execute args", ctx do
      [%Carol.Episode{id: id} | _] = episodes = assert_episodes(ctx)

      assert {[opts: [ack: :host]], [cmd: :on, id: ^id]} = Carol.Episode.execute_args([], :active, episodes)
    end

    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    test "execute_args/2 returns execute args for known id", ctx do
      episodes = assert_episodes(ctx)

      # two element tuple:
      #  - elem0 = execute args
      #  - elem1 = default args
      assert {[opts: [ack: :host], equipment: "equip"], [cmd: :on, id: "Past -3"]} =
               Carol.Episode.execute_args([equipment: "equip"], "Past -3", episodes)
    end

    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    test "execute_args/2 returns empty list for unknown id", ctx do
      episodes = assert_episodes(ctx)

      assert {[], []} = Carol.Episode.execute_args([], "Unknown", episodes)
    end
  end

  describe "Sally.Episode.status_from_list/2" do
    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    test "creates list of status maps", ctx do
      episodes = assert_episodes(ctx)

      assert [<<_::binary>>, <<_::binary>> | _] =
               Carol.Episode.status_from_list(episodes, ctx.opts ++ [format: :humanized])
    end
  end

  def episodes_summary(%{episodes: episodes, ref_dt: ref_dt}) do
    %{episodes_summary: Enum.map(episodes, fn e -> {e.id, Timex.diff(e.at, ref_dt, :milliseconds)} end)}
  end

  def episodes_summary(_ctx), do: :ok

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  defp episodes_add(ctx), do: Carol.EpisodeAid.add(ctx)
  defp opts_add(ctx), do: Carol.OptsAid.add(ctx)
end
