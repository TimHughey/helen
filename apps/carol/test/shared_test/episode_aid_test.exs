defmodule CarolEpisodeAidTest do
  use ExUnit.Case, async: true

  @moduletag carol: true, carol_episode_aid: true

  setup [:opts_add, :episodes_add]

  defmacro assert_counts(results, want_counts) do
    quote bind_quoted: [results: results, want_counts: want_counts] do
      acc = [future: 0, now: 0, past: 0]

      kw_update = fn {k, _}, acc -> Keyword.update(acc, k, 1, fn x -> x + 1 end) end

      summary = Enum.reduce(results, acc, fn kv, acc -> kw_update.(kv, acc) end)

      summary = Enum.sort(summary)
      want_counts = Enum.sort(want_counts)

      assert summary = want_counts
    end
  end

  defmacro assert_episodes(ctx, want_counts) do
    quote bind_quoted: [ctx: ctx, want_counts: want_counts] do
      episodes = ctx.episodes
      ref_dt = ctx.ref_dt

      for episode <- episodes do
        assert %Carol.Episode{} = episode

        diff_ms = Timex.diff(episode.at, ref_dt, :milliseconds)

        cond do
          episode.id =~ ~r/Now/ and diff_ms == 0 -> {:now, :passed}
          episode.id =~ ~r/Past/ and diff_ms < 0 -> {:past, :passed}
          episode.id =~ ~r/Future/ and diff_ms > 0 -> {:future, :passed}
          true -> {episode.id, diff_ms}
        end
      end
      |> assert_passed()
      |> assert_counts(want_counts)
    end
  end

  defmacro assert_passed(results) do
    quote bind_quoted: [results: results] do
      Enum.each(results, fn {type, _} = r -> assert {^type, :passed} = r end)

      results
    end
  end

  describe "Sally.EpisodeAid.add/1" do
    @tag episodes_add: {:mixed, [analyze: false, past: 3, now: 1, future: 3]}
    test "creates a mix of episodes: past, now, future", ctx do
      assert_episodes(ctx, past: 3, now: 1, future: 3)
    end

    @tag episodes_add: {:mixed, [analyze: false, past: 3, future: 3]}
    test "creates a mix of episodes: past, future", ctx do
      assert_episodes(ctx, past: 3, now: 0, future: 3)
    end

    @tag episodes_add: {:past, [analyze: false, count: 10]}
    test "creates past episodes", ctx do
      assert_episodes(ctx, past: 10, now: 0, future: 0)
    end

    @tag episodes_add: {:future, [analyze: false, count: 10]}
    test "creates future episodes", ctx do
      assert_episodes(ctx, past: 0, now: 0, future: 10)
    end
  end

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  defp episodes_add(ctx), do: Carol.EpisodeAid.add(ctx)
  defp opts_add(ctx), do: Carol.OptsAid.add(ctx)
end
