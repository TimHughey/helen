defmodule CarolServerTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag carol: true, carol_server: true

  setup [:equipment_add, :opts_add, :episodes_add, :state_add]
  setup [:memo_add, :start_args_add, :start_supervised_add, :handle_add]
  setup [:missing_opts_add]
  setup [:ctx_puts]

  defmacro assert_cmd_echoed(ctx, cmd) do
    quote location: :keep, bind_quoted: [ctx: ctx, cmd: cmd] do
      equipment = Should.Be.Map.with_key(ctx, :equipment)

      receive do
        {:echo, %Alfred.ExecCmd{} = ec} -> Should.Be.Struct.with_all_key_value(ec, Alfred.ExecCmd, cmd: cmd)
      after
        100 -> assert false, Should.msg(:timeout, "should have received ExecCmd")
      end
    end
  end

  describe "Carol.Server starts supervised" do
    @tag start_args_add: {:app, :carol, CarolNoEpisodes, :first_instance}
    test "with empty config", ctx do
      want_kv = [episodes: [], equipment: "first instance pwm", server_name: ctx.server_name]

      ctx.child_spec
      |> start_supervised()
      |> Should.Be.Ok.tuple_with_pid()
      |> Should.Be.Server.with_state()
      |> Should.Contain.kv_pairs(want_kv)
    end

    @tag start_args_add: {:app, :carol, CarolTest, :front_chandelier}
    test "with epsiodes", ctx do
      want_kv = [cmd_live: :none, exec_result: :none, notify_at: :none, server_name: ctx.server_name]

      ctx.child_spec
      |> start_supervised()
      |> Should.Be.Ok.tuple_with_pid()
      |> Should.Be.Server.with_state()
      |> Should.Contain.kv_pairs(want_kv)
      |> tap(fn state -> Should.Be.List.with_length(state.episodes, 3) end)
      |> tap(fn state -> Should.Be.Struct.named(state.ticket, Alfred.Notify.Ticket) end)
    end

    @tag start_args_add: {:app, :carol, CarolWithEpisodes, :first_instance}
    test "with episodes (alt)", ctx do
      server = ctx.server_name

      want_kv = [cmd_live: :none, exec_result: :none, notify_at: :none, server_name: server]
      want_keys = Keyword.keys(want_kv)

      ctx.child_spec
      |> start_supervised()
      |> Should.Be.Ok.tuple_with_pid()
      |> Should.Be.Server.with_state()

      # validate state and indirectly test Carol.state/2
      Carol.state(server, want_keys) |> Should.Contain.kv_pairs(want_kv)
      Carol.state(server, []) |> Should.Be.NonEmpty.list()
      Carol.state(server, :episodes) |> Should.Be.List.with_length(3)
      Carol.state(server, :ticket) |> Should.Be.Map.with_keys([:name, :ref, :opts])
    end
  end

  describe "Carol.Server runs" do
    # NOTE: to not run this test use: mix test --exclude long
    @tag long: true
    @tag equipment_add: [cmd: "off"]
    @tag episodes_add: {:short, [future: 12, now: 1, past: 1]}
    @tag start_args_add: {:new_app, :carol, __MODULE__, :short_episodes}
    @tag start_supervised_add: []
    test "live plus multiple short episodes", %{server_name: server_name} do
      for x when x <= 500 <- 1..500, reduce: :query_active do
        "Future 11" = active_id ->
          active_id

        # race condition at startup if Now 1 is active
        "Future 12" = active_id ->
          active_id

        _ ->
          Process.sleep(10)

          Carol.active_episode(server_name)
      end
      |> Should.Be.equal("Future 11")
    end
  end

  describe "Carol.Server operations" do
    @tag start_args_add: {:app, :carol, CarolWithEpisodes, :first_instance}
    @tag start_supervised_add: []
    test "can be paused, resumed and restarted", ctx do
      pid = ctx.server_pid
      server_name = ctx.server_name

      Carol.pause(pid, []) |> Should.Be.equal(:pause)
      Carol.state(pid, :ticket) |> Should.Be.equal(:pause)

      Carol.resume(pid, :resume) |> Should.Be.ok()
      Carol.state(pid, :ticket) |> Should.Contain.keys([:ref, :name])

      Carol.restart(pid, []) |> Should.Be.equal(:restarting)

      Process.sleep(100)
      new_pid = GenServer.whereis(server_name) |> Should.Be.pid()
      refute new_pid == pid, Should.msg(new_pid, "new pid should be different", pid)
      Carol.active_episode(new_pid) |> Should.Be.binary()
    end
  end

  describe "Carol.Server.handle_call/3" do
    @tag equipment_add: [cmd: "off"]
    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    @tag state_add: [bootstrap: true]
    test "processes :restart message", ctx do
      Carol.Server.handle_call(:restart, self(), ctx.state)
      |> Should.Be.Reply.stop_normal(:restarting)
    end
  end

  #
  # describe "Carol.Server.call/2" do
  #   @tag equipment_add: [], program_add: :future_programs
  #   @tag start_args_add: [:programs]
  #   @tag skip: true
  #   test "calls server with message", ctx do
  #     start_supervised({Server, ctx.start_args})
  #     |> Should.Be.Ok.tuple_with_pid()
  #     |> Should.Be.Server.with_state()
  #     |> Should.Contain.kv_pairs(server_name: ctx.server_name)
  #
  #     Server.call(ctx.server_name, :restart)
  #     |> Should.Be.equal(:restarting)
  #   end
  # end
  #
  describe "Carol.Server.handle_continue/2 :bootstrap" do
    @tag equipment_add: []
    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    @tag state_add: [bootstrap: true, raw: true]
    test "handles successful start notifies", ctx do
      # first call, starts notifies recurses to check result
      new_state = Should.Be.NoReply.continue_term(ctx.state, :bootstrap)

      # second call, vslidates ticket is %Ticket{}
      Carol.Server.handle_continue(:bootstrap, new_state)
      |> Should.Be.NoReply.with_state(:timeout)
      |> Should.Contain.types(ticket: {:struct, Alfred.Notify.Ticket})
    end

    @tag equipment_add: []
    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    @tag state_add: []
    test "retries failed start notifies", ctx do
      # simulate start notifies failure
      new_state = Carol.State.save_ticket({:no_server, Module}, ctx.state)

      Carol.Server.handle_continue(:bootstrap, new_state)
      |> Should.Be.NoReply.continue_term(:bootstrap)
    end
  end

  describe "Carol.Server.handle_continue/2 :tick" do
    @tag equipment_add: []
    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    @tag state_add: [bootstrap: true]
    test "executes a cmd when a program is live", ctx do
      Carol.Server.handle_continue(:tick, ctx.state)
      |> Should.Be.NoReply.with_state(:timeout)
      |> Should.Contain.kv_pairs(cmd_live: "on")
      |> tap(fn state -> Should.Contain.kv_pairs(state.exec_result, cmd: "on") end)

      assert_cmd_echoed(ctx, "on")
    end
  end

  describe "Carol.Server.handle_info/2 handles Alfred" do
    @tag equipment_add: []
    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    @tag state_add: [bootstrap: true], memo_add: [missing?: true]
    test "missing Memo", ctx do
      Carol.Server.handle_info({Alfred, ctx.memo}, ctx.state)
      |> Should.Be.NoReply.with_state(:timeout)
    end

    @tag equipment_add: []
    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    @tag state_add: [bootstrap: true], memo_add: []
    test "nominal Memo", ctx do
      Carol.Server.handle_info({Alfred, ctx.memo}, ctx.state)
      |> Should.Be.NoReply.continue_term(:tick)
    end
  end

  describe "Carol.Server.handle_info/2 handles Broom" do
    @tag equipment_add: [cmd: "on", rc: :pending]
    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    @tag state_add: [bootstrap: true]
    test "TrackerEntry with matching refid", ctx do
      # NOTE: handle_continue/2 call required to trigger execute
      new_state =
        Carol.Server.handle_continue(:tick, ctx.state)
        |> Should.Be.NoReply.with_state(:timeout)

      er = new_state.exec_result
      te = %Broom.TrackerEntry{cmd: er.cmd, refid: er.refid}

      Carol.Server.handle_info({Broom, te}, new_state)
      |> Should.Be.NoReply.with_state(:timeout)
      |> Should.Contain.key(:cmd_live, :value)
      |> Should.Contain.binaries(["PENDING", "on"])
    end
  end

  def episodes_summary(%{episodes: episodes, ref_dt: ref_dt} = ctx) do
    episodes_summary(episodes, ref_dt)

    ctx
  end

  def episodes_summary(%{episodes: episodes}, ref_dt) do
    episodes_summary(episodes, ref_dt)

    episodes
  end

  def episodes_summary(episodes, ref_dt) do
    for e <- episodes do
      diff = Timex.diff(e.at, ref_dt, :milliseconds)

      {e.id, diff}
    end
    |> pretty_puts()

    episodes
  end

  defp ctx_puts(%{ctx_puts: what} = ctx) do
    ctx = Map.delete(ctx, :ctx_puts)

    case what do
      [] -> pretty_puts(ctx)
      :keys -> Map.keys(ctx) |> Enum.sort() |> pretty_puts()
    end

    ctx
  end

  defp ctx_puts(_), do: :ok

  defp equipment_add(ctx), do: Alfred.NamesAid.equipment_add(ctx)

  defp handle_add(%{handle_add: opts, state: state} = ctx) when opts != [] do
    opts_map = Enum.into(opts, %{})

    case opts_map do
      %{continue: msg} -> Carol.Server.handle_continue(msg, state)
      %{func: func} -> apply(func, [Map.get(ctx, opts[:msg]), state])
    end
    |> Should.Be.NoReply.with_state()
    |> then(fn new_state -> %{new_state: new_state} end)
  end

  defp handle_add(_ctx), do: :ok

  defp memo_add(ctx), do: Alfred.NotifyAid.memo_add(ctx)

  defp missing_opts_add(ctx) do
    Map.put_new(ctx, :server_name, __MODULE__)
  end

  defp opts_add(ctx), do: Carol.OptsAid.add(ctx)
  defp episodes_add(ctx), do: Carol.EpisodeAid.add(ctx)
  defp start_args_add(ctx), do: Carol.StartArgsAid.add(ctx)

  defp start_supervised_add(%{start_supervised_add: _} = ctx) do
    case ctx do
      %{child_spec: child_spec} -> start_supervised(child_spec) |> Should.Be.Ok.tuple_with_pid()
      _ -> :no_child_spec
    end
    |> then(fn pid -> %{server_pid: pid} end)
  end

  defp start_supervised_add(_x), do: :ok

  defp state_add(ctx), do: Carol.StateAid.add(ctx)
end
