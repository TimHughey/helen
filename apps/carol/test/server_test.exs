defmodule CarolServerTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag carol: true, carol_server: true

  setup [:equipment_add, :opts_add, :episodes_add, :state_add]
  setup [:memo_add, :start_args_add, :start_supervised_add]
  setup [:missing_opts_add]

  defmacro msg(lhs, text, rhs) do
    quote bind_quoted: [lhs: lhs, text: text, rhs: rhs] do
      [Macro.to_string(lhs), text, Macro.to_string(rhs), "\n"]
      |> Enum.join("\n")
    end
  end

  defmacro assert_cmd_echoed(ctx, cmd) do
    quote location: :keep, bind_quoted: [ctx: ctx, cmd: cmd] do
      assert %{equipment: <<_::binary>>} = ctx

      assert_receive {:echo, %Alfred.Status{}}, 100
      assert_receive {:echo, %Alfred.Execute{detail: %{cmd: ^cmd}}}, 100
    end
  end

  describe "Carol.Server starts supervised" do
    @tag start_args_add: {:app, :carol, CarolNoEpisodes, :first_instance}
    test "with empty config", %{child_spec: child_spec, server_name: server_name} do
      assert {:ok, pid} = start_supervised(child_spec)

      assert %Carol.State{episodes: [], equipment: "first instance pwm", server_name: ^server_name} =
               :sys.get_state(pid)
    end

    @tag start_args_add: {:app, :carol, CarolTest, :front_chandelier}
    test "with epsiodes", %{child_spec: child_spec, server_name: server_name} do
      assert {:ok, pid} = start_supervised(child_spec)

      assert %Carol.State{
               cmd_live: :none,
               exec_result: :none,
               notify_at: :none,
               server_name: ^server_name,
               episodes: [%Carol.Episode{}, %Carol.Episode{}, %Carol.Episode{}],
               ticket: %Alfred.Ticket{}
             } = :sys.get_state(pid)
    end

    @tag start_args_add: {:app, :carol, CarolWithEpisodes, :first_instance}
    test "with episodes (alt)", %{child_spec: child_spec, server_name: server_name} do
      assert {:ok, pid} = start_supervised(child_spec)

      assert %Carol.State{
               cmd_live: :none,
               exec_result: :none,
               notify_at: :none,
               server_name: ^server_name,
               episodes: [%Carol.Episode{}, %Carol.Episode{}, %Carol.Episode{}],
               ticket: %Alfred.Ticket{}
             } = :sys.get_state(pid)

      assert [cmd_live: :none, exec_result: :none, notify_at: :none, server_name: ^server_name] =
               Carol.state(server_name, [:cmd_live, :exec_result, :notify_at, :server_name])

      assert [_ | _] = Carol.state(server_name, [])
      assert [%Carol.Episode{}, %Carol.Episode{}, %Carol.Episode{}] = Carol.state(server_name, :episodes)
      assert %{name: _, ref: _, opts: _} = Carol.state(server_name, :ticket)
    end
  end

  describe "Carol.Server runs" do
    @tag equipment_add: [cmd: "off"]
    @tag episodes_add: {:short, [future: 12, now: 1, past: 1]}
    @tag start_args_add: {:new_app, :carol, __MODULE__, :short_episodes}
    @tag start_supervised_add: []
    test "live plus multiple short episodes", %{server_name: server_name} do
      # ensure the server starts with Now 1
      assert "Now 1" = Carol.active_episode(server_name)

      # get the list of episode ids and count of episodes so we can remove activated
      # episodes from the total episode id list
      episode_ids = Carol.state(server_name, :episodes) |> Enum.map(fn %{id: id} -> id end)
      episode_count = Enum.count(episode_ids)

      # allow the server to activate 10 episodes
      want_remaining = episode_count - 4

      ms_to_run = Timex.Duration.from_seconds(10) |> Timex.Duration.to_milliseconds() |> trunc()
      sleep_ms = 10

      remaining_ids =
        for _x <- 1..ms_to_run//sleep_ms, reduce: episode_ids do
          # pass time until we have seen enough episodes activate
          acc when length(acc) >= want_remaining ->
            # allow time to pass
            Process.sleep(sleep_ms)

            active_id = Carol.active_episode(server_name)

            # the new accumulator is the list of episode ids with the active id removed
            Enum.reject(acc, fn id -> id == active_id end)

          # enough episodes have activated, wrap up reduction
          acc ->
            acc
        end

      assert Enum.count(remaining_ids) < episode_count
    end
  end

  describe "Carol.Server operations" do
    @tag start_args_add: {:app, :carol, CarolWithEpisodes, :first_instance}
    @tag start_supervised_add: []
    test "can be paused, resumed and restarted", ctx do
      pid = ctx.server_pid
      server_name = ctx.server_name

      assert :pause == Carol.pause(pid, [])
      assert :pause == Carol.state(pid, :ticket)

      assert :ok == Carol.resume(pid, :resume)
      assert %{name: _, opts: _, ref: _} = Carol.state(pid, :ticket)

      assert :restarting == Carol.restart(pid, [])

      # allow server to restart
      Process.sleep(10)

      assert new_pid = GenServer.whereis(server_name)
      refute new_pid == pid, msg(new_pid, "new pid should be different", pid)
    end
  end

  describe "Carol.Server.handle_call/3" do
    @tag equipment_add: [cmd: "off"]
    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    @tag state_add: [bootstrap: true]
    test "processes :restart message", ctx do
      assert {:stop, :normal, :restarting, %Carol.State{}} =
               Carol.Server.handle_call(:restart, self(), ctx.state)
    end
  end

  describe "Carol.Server.handle_continue/2 :bootstrap" do
    @tag equipment_add: []
    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    @tag state_add: [bootstrap: true, raw: true]
    test "handles successful start notifies", ctx do
      # NOTE: when raw: true start_add returns the actual reply from handle_continue/2
      assert {:noreply, %Carol.State{} = new_state, {:continue, :bootstrap}} = ctx.state

      # second call, vslidates ticket is %Ticket{}
      assert {:noreply, %Carol.State{ticket: %Alfred.Ticket{}}, timeout} =
               Carol.Server.handle_continue(:bootstrap, new_state)

      assert is_integer(timeout)
    end

    @tag equipment_add: []
    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    @tag state_add: []
    test "retries failed start notifies", ctx do
      # simulate start notifies failure
      new_state = Carol.State.save_ticket({:no_server, Module}, ctx.state)

      assert {:noreply, %Carol.State{}, {:continue, :bootstrap}} =
               Carol.Server.handle_continue(:bootstrap, new_state)
    end
  end

  describe "Carol.Server.handle_continue/2 :tick" do
    @tag equipment_add: []
    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    @tag state_add: [bootstrap: true]
    test "executes a cmd when a program is live", ctx do
      assert {:noreply, %Carol.State{exec_result: %Alfred.Execute{detail: %{cmd: "on"}}}, _timeout} =
               Carol.Server.handle_continue(:tick, ctx.state)

      assert_cmd_echoed(ctx, "on")
    end
  end

  describe "Carol.Server.handle_info/2 handles Alfred" do
    @tag equipment_add: []
    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    @tag state_add: [bootstrap: true], memo_add: [missing?: true]
    test "missing Memo", ctx do
      assert {:noreply, %Carol.State{}, _} = Carol.Server.handle_info({Alfred, ctx.memo}, ctx.state)
    end

    @tag equipment_add: []
    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    @tag state_add: [bootstrap: true], memo_add: []
    test "nominal Memo", ctx do
      assert {:noreply, %Carol.State{}, {:continue, :tick}} =
               Carol.Server.handle_info({Alfred, ctx.memo}, ctx.state)
    end
  end

  describe "Carol.Server.handle_info/2 handles Alfred.Broom" do
    @tag skip: false
    @tag equipment_add: [cmd: "on", rc: :pending]
    @tag episodes_add: {:mixed, [past: 3, now: 1, future: 3]}
    @tag state_add: [bootstrap: true]
    test "TrackerEntry with matching refid", ctx do
      # NOTE: handle_continue/2 call required to trigger execute

      noreply_tuple = Carol.Server.handle_continue(:tick, ctx.state)

      assert {:noreply, %Carol.State{} = new_state, _timeout} = noreply_tuple

      execute = new_state.exec_result
      broom = %Alfred.Broom{tracked_info: %{cmd: execute.detail.cmd}, refid: execute.detail.refid}

      assert {:noreply, %Carol.State{cmd_live: cmd_live}, _timeout} =
               Carol.Server.handle_info({Alfred, broom}, new_state)

      assert cmd_live =~ ~r/^PENDING\s\{on\}/
    end
  end

  defp equipment_add(ctx), do: Alfred.NamesAid.equipment_add(ctx)

  defp memo_add(ctx), do: Alfred.NotifyAid.memo_add(ctx)

  defp missing_opts_add(ctx) do
    Map.put_new(ctx, :server_name, __MODULE__)
  end

  defp opts_add(ctx), do: Carol.OptsAid.add(ctx)
  defp episodes_add(ctx), do: Carol.EpisodeAid.add(ctx)
  defp start_args_add(ctx), do: Carol.StartArgsAid.add(ctx)

  defp start_supervised_add(%{start_supervised_add: _, child_spec: child_spec}) do
    assert {:ok, pid} = start_supervised(child_spec)

    %{server_pid: pid}
  end

  defp start_supervised_add(_x), do: :ok

  defp state_add(ctx), do: Carol.StateAid.add(ctx)
end
