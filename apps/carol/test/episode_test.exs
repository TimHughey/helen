defmodule CarolEpisodeTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag carol: true, carol_episode: true

  @tz "America/New_York"

  setup [:opts_add, :episodes_add]

  defmacro assert_active(episode, ref_dt) do
    quote bind_quoted: [episode: episode, ref_dt: ref_dt] do
      before? = Timex.compare(episode.at, ref_dt) <= 0
      assert before?, Should.msg(episode, "active should be less than or equal to ref_dt", ref_dt)
    end
  end

  defmacro assert_rest(active, rest, ref_dt) do
    quote bind_quoted: [active: active, rest: rest, ref_dt: ref_dt] do
      for episode <- rest, reduce: active do
        previous ->
          after? = Timex.compare(episode.at, previous.at) >= 0
          assert after?, Should.msg(episode, "episode should be greater than previous", previous)

          episode
      end
    end
  end

  defmacro assert_episodes(ctx) do
    quote bind_quoted: [ctx: ctx] do
      episode_count = episode_count(ctx)

      episodes =
        ctx.episodes
        |> Should.Be.List.with_length(episode_count, unwrap: false)
        |> Should.Be.List.of_type({:struct, Carol.Episode})

      cond do
        episode_count >= 2 ->
          [active | rest] = episodes
          assert_active(active, ctx.ref_dt)
          assert_rest(active, rest, ctx.ref_dt)

        episode_count == 1 ->
          [active] = episodes
          assert_active(active, ctx.ref_dt)

        # empty episode list
        true ->
          assert true
      end

      episodes
    end
  end

  defp episode_count(%{episodes_add: {_, []}}), do: 1

  defp episode_count(%{episodes_add: {_, add_opts}}) do
    for what <- add_opts, reduce: 0 do
      acc ->
        case what do
          {key, count} when key in [:future, :now, :past] -> acc + count
          {:count, count} -> count
          _ -> acc
        end
    end
  end

  defp episode_count(_), do: 0

  describe "Sally.Episode.new/1" do
    test "creates valid Episode with a Solar sun ref" do
      [event: "astro rise"]
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
    test "handle list of past, now and future episodes", ctx do
      assert_episodes(ctx)
    end

    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3, overnight: 1]}
    test "handle list of past, now, overnight and future episodes", ctx do
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
      assert_episodes(ctx)
      |> Carol.Episode.ms_until_next_episode(ctx.opts)
      |> Should.Be.equal(2000)
    end

    @tag episodes_add: {:future, [count: 10, minutes: 1]}
    test "handles list of only future episodes", ctx do
      assert_episodes(ctx)
      |> Carol.Episode.ms_until_next_episode(ctx.opts)
      |> Should.Be.equal(60_000)
    end
  end

  describe "Sally.Episode misc" do
    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    test "put_execute/2 updates :execute for the given id", ctx do
      episodes = assert_episodes(ctx)

      {"Future 2", [cmd: "updated", params: [type: "random"]]}
      |> Carol.Episode.put_execute(episodes)
      |> Enum.find(fn %{id: id} -> id == "Future 2" end)
      |> Should.Contain.key(:execute, :value)
      |> Should.Contain.kv_pairs(cmd: "updated")
    end

    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    test "execute_args/2 returns active execute args", ctx do
      episodes = assert_episodes(ctx)

      Carol.Episode.execute_args(:active, episodes)
      |> Should.Contain.key(:cmd)
    end

    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    test "execute_args/2 returns execute args for known id", ctx do
      episodes = assert_episodes(ctx)

      Carol.Episode.execute_args("Past -3", episodes)
      |> Should.Contain.key(:cmd)
    end

    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    test "execute_args/2 returns empty list for unknown id", ctx do
      episodes = assert_episodes(ctx)

      Carol.Episode.execute_args("Unknown", episodes)
      |> Should.Be.List.empty()
    end
  end

  describe "Sally.Episode.status_from_list/2" do
    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    test "creates list of status maps", ctx do
      assert_episodes(ctx)
      |> Carol.Episode.status_from_list(ctx.opts ++ [format: :humanized])
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
