defmodule CarolEpisodeTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag carol: true, carol_episode: true

  @tz "America/New_York"

  setup [:opts_add, :episodes_add, :sim_add]

  defmacro assert_active(episode, ref_dt) do
    quote bind_quoted: [episode: episode, ref_dt: ref_dt] do
      before? = Timex.compare(episode.at, ref_dt) <= 0
      assert before?, Should.msg(episode, "active should be less than or equal to ref_dt", ref_dt)
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

  defmacro assert_sim(want_order) do
    quote bind_quoted: [want_order: want_order] do
      %{episodes: episodes, opts: opts, ref_dt: ref_dt, sim_ms: sim_ms, step_ms: step_ms} = var!(ctx)

      sim_measure = Map.get(var!(ctx), :sim_measure, true)

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
            assert active == expect_active, Should.msg({active, expect_active}, "should be equal", episodes)

            {active, episodes, want_order_rest}
          else
            {active, episodes, want_order}
          end
      end
    end
  end

  defp episode_count(%{episodes_add: {_, []}}), do: 1

  defp episode_count(%{episodes_add: {_, add_opts}}) do
    for what <- add_opts, reduce: 0 do
      acc ->
        case what do
          {key, count} when key in [:future, :now, :past, :yesterday] -> acc + count
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
      Carol.Episode.analyze_episodes([], ctx.opts)
      |> Should.Be.List.empty()
    end
  end

  describe "Sally.Episode timeline" do
    @tag skip: true
    @tag timeout: 10 * 1000
    @tag sim_days: 3, step_ms: 1000
    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    @tag want_order: ["Now 1", "Future 1", "Future 2", "Future 3", "Past -3", "Past -2", "Past -1"]
    test "simulated 48hrs", ctx do
      want_order = ctx.want_order

      assert_sim(want_order)
    end

    @tag timeout: 10 * 1000
    @tag sim_days: 3, step_ms: 1000
    @tag want_order: ["Overnight", "Day", "Evening"]
    @tag episodes_add: {:sim, :porch}
    test "porch simulation", ctx do
      active = Carol.Episode.active_id(ctx.episodes)
      want_order = Enum.drop_while(ctx.want_order, fn x -> x != active end)

      assert_sim(want_order)
    end

    @tag timeout: 10 * 1000
    @tag sim_days: 3, step_ms: 1000
    @tag want_order: ["Day", "Night"]
    @tag episodes_add: {:sim, :greenhouse}
    test "greenhouse simulation", ctx do
      active = Carol.Episode.active_id(ctx.episodes)
      want_order = Enum.drop_while(ctx.want_order, fn x -> x != active end)

      assert_sim(want_order)
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
      |> Should.Be.equal(3000)
    end

    @tag episodes_add: {:future, [count: 10, minutes: 1]}
    test "handles list of only future episodes", ctx do
      assert_episodes(ctx)
      |> Carol.Episode.ms_until_next_episode(ctx.opts)
      |> Should.Be.equal(63_000)
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

      Carol.Episode.execute_args([], :active, episodes)
      |> Should.Be.Tuple.with_size(2)
      |> tap(fn {args, _} -> Should.Contain.key(args, :cmd) end)
    end

    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    test "execute_args/2 returns execute args for known id", ctx do
      episodes = assert_episodes(ctx)
      want_kv = [equipment: "equip", cmd: :on]

      Carol.Episode.execute_args([equipment: "equip"], "Past -3", episodes)
      |> Should.Be.Tuple.with_size(2)
      |> tap(fn {args, _} -> Should.Contain.kv_pairs(args, want_kv) end)
    end

    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    test "execute_args/2 returns empty list for unknown id", ctx do
      episodes = assert_episodes(ctx)

      Carol.Episode.execute_args([], "Unknown", episodes)
      |> Should.Be.match({[], []})
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
