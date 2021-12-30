defmodule CarolEpisodeSimTest do
  use ExUnit.Case, async: true

  @moduletag carol: true, carol_episode_sim: true

  setup [:opts_add, :episodes_add, :sim_add]

  defmacro assert_sim(want_order) do
    quote bind_quoted: [want_order: want_order] do
      import Should, only: [msg: 3]

      %{episodes: episodes, opts: opts, ref_dt: ref_dt, sim_ms: sim_ms, step_ms: step_ms} = var!(ctx)

      sim_measure = Map.get(var!(ctx), :sim_measure, false)

      for ms when ms < sim_ms <- 0..sim_ms//1000, reduce: {:none, episodes, want_order} do
        {prev_active, prev_episodes, want_order} ->
          {timestamp, episodes} =
            Timex.Duration.measure(fn ->
              Carol.Episode.analyze_episodes(prev_episodes, shift_ref_dt(opts, ms))
            end)

          if prev_active == :none and sim_measure do
            episodes_add = Map.get(var!(ctx), :episodes_add)
            elapsed = Timex.format_duration(timestamp, :humanized)
            ["\n", inspect(episodes_add), " ", elapsed] |> IO.puts()
          end

          active = Carol.Episode.active_id(episodes)

          if active != prev_active do
            [expect_active | want_order_rest] = want_order
            assert active == expect_active, msg({active, expect_active}, "should be equal", episodes)

            {active, episodes, want_order_rest}
          else
            {active, episodes, want_order}
          end
      end
    end
  end

  describe "Sally.Episode simulation" do
    # @tag skip: true
    @tag timeout: 10 * 1000
    @tag sim_days: 30, step_ms: 1000
    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    @tag want_order: ["Now 1", "Future 1", "Future 2", "Future 3", "Past -3", "Past -2", "Past -1"]
    test "mixed episodes using Carol.Episode.ms_until_next_episode/2 to advance ref_dt", ctx do
      import Should, only: [msg: 3]

      # calculate the number of reductions we need to simulate the requested sim days
      %{episodes_add: {_, add_opts}} = ctx
      sim_episodes = Enum.reduce(add_opts, 0, fn {_k, val}, acc -> acc + val end) * ctx.sim_days

      for _ <- 1..sim_episodes, reduce: {:none, ctx.episodes, ctx.want_order, ctx.opts} do
        {prev_active, prev_episodes, want_order, sched_opts} ->
          # create refreshed episodes
          episodes = Carol.Episode.analyze_episodes(prev_episodes, sched_opts)

          # calculate how long until the next episode activates
          ms_until_next = Carol.Episode.ms_until_next_episode(episodes, sched_opts)

          # get the new active episode id
          active = Carol.Episode.active_id(episodes)

          # ensure the active episode changed
          assert active != prev_active

          # pluck the next wanted episode off the list
          [expect_active | want_order_rest] = want_order

          # ensure the active episode is indeed the one we expect
          assert active == expect_active, msg({active, expect_active}, "should be equal", episodes)

          # shift ref_dt by the milliseconds until the next episode
          sched_opts = shift_ref_dt(sched_opts, ms_until_next)

          # build accumulator
          {active, episodes, want_order_rest, sched_opts}
      end
    end

    @tag timeout: 10 * 1000
    @tag sim_days: 2, step_ms: 1000
    @tag want_order: ["Overnight", "Day", "Evening"]
    @tag episodes_add: {:sim, :porch}
    test "porch advancing ref_dt one (1) second at a time", ctx do
      active = Carol.Episode.active_id(ctx.episodes)
      want_order = Enum.drop_while(ctx.want_order, fn x -> x != active end)

      assert_sim(want_order)
    end

    @tag timeout: 10 * 1000
    @tag sim_days: 3, step_ms: 1000
    @tag want_order: ["Day", "Night"]
    @tag episodes_add: {:sim, :greenhouse}
    test "greenhouse advancing ref_dt one (1) second at a time", ctx do
      active = Carol.Episode.active_id(ctx.episodes)
      want_order = Enum.drop_while(ctx.want_order, fn x -> x != active end)

      assert_sim(want_order)
    end
  end

  defp episodes_add(ctx), do: Carol.EpisodeAid.add(ctx)
  defp opts_add(ctx), do: Carol.OptsAid.add(ctx)

  defp sim_add(%{ref_dt: start_dt, sim_days: sim_days, want_order: want_order}) do
    finish_dt = start_dt |> Timex.shift(days: sim_days)
    sim_ms = Timex.diff(finish_dt, start_dt, :milliseconds)

    sim_days = 1..(sim_days + 1)
    want_order = Enum.reduce(sim_days, [], fn _, acc -> [want_order | acc] end)

    %{sim_ms: sim_ms, want_order: List.flatten(want_order)}
  end

  defp sim_add(_), do: :ok

  defp shift_ref_dt(opts, ms) do
    Timex.shift(opts[:ref_dt], milliseconds: ms)
    |> then(fn ref_dt -> Keyword.replace(opts, :ref_dt, ref_dt) end)
  end
end
