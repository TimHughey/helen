defmodule CarolServerTest do
  use ExUnit.Case, async: true
  use Should

  alias Alfred.{ExecCmd, ExecResult}

  alias Carol.{Server, State}

  @moduletag carol: true, carol_server: true

  setup_all do
    {:ok, %{alfred: AlfredSim, server_name: __MODULE__}}
  end

  setup [:opts_add, :equipment_add, :program_add, :state_add]
  setup [:memo_add, :start_args_add, :handle_add]

  defmacro assert_cmd_echoed(ctx, cmd) do
    quote location: :keep, bind_quoted: [ctx: ctx, cmd: cmd] do
      equipment = Should.Be.Map.with_key(ctx, :equipment)

      receive do
        {:echo, %ExecCmd{} = ec} -> Should.Be.Struct.with_all_key_value(ec, ExecCmd, cmd: cmd)
      after
        100 -> assert false, Should.msg(:timeout, "should have received ExecCmd")
      end
    end
  end

  describe "Carol.Server starts supervised" do
    @tag equipment_add: [], start_args_add: []
    test "without programs", ctx do
      ctx.start_args
      |> Server.child_spec()
      |> then(fn spec -> start_supervised(Server, spec) end)
      |> Should.Be.Ok.tuple_with_pid()
      |> Should.Be.Server.with_state()
      |> tap(fn state -> Should.Contain.kv_pairs(state, server_name: ctx.server_name) end)
    end

    @tag equipment_add: [], program_add: :future_programs
    @tag start_args_add: [want: [:programs]]
    test "with programs", ctx do
      start_supervised({Server, ctx.start_args})
      |> Should.Be.Ok.tuple_with_pid()
      |> Should.Be.Server.with_state()
      |> Should.Contain.kv_pairs(server_name: ctx.server_name)
      |> tap(fn state -> Should.Be.List.with_length(state.programs, 2) end)
    end

    @tag equipment_add: [], programs_add: :future_programs
    @tag start_args_add: [init_args_fn: true, want: [:programs]]
    test "using an init args function", ctx do
      start_supervised({Server, ctx.start_args})
      |> Should.Be.Ok.tuple_with_pid()
      |> Should.Be.Server.with_state()
      |> tap(fn state -> Should.Contain.kv_pairs(state, server_name: ctx.server_name) end)
      |> Should.Contain.kv_pairs(server_name: ctx.server_name)
    end
  end

  describe "Carol.Server.handle_call/3" do
    @tag equipment_add: [cmd: "off"], program_add: :future_programs
    @tag state_add: [bootstrap: true]
    test "processes :restart message", ctx do
      Server.handle_call(:restart, self(), ctx.state)
      |> Should.Be.Reply.stop_normal(:restarting)
    end
  end

  describe "Carol.Server.call/2" do
    @tag equipment_add: [], program_add: :future_programs
    @tag start_args_add: [:programs]
    test "calls server with message", ctx do
      start_supervised({Server, ctx.start_args})
      |> Should.Be.Ok.tuple_with_pid()
      |> Should.Be.Server.with_state()
      |> Should.Contain.kv_pairs(server_name: ctx.server_name)

      Server.call(ctx.server_name, :restart)
      |> Should.Be.equal(:restarting)
    end
  end

  describe "Carol.Server.handle_continue/2 :bootstap" do
    @tag equipment_add: [], program_add: :future_programs
    @tag state_add: [bootstrap: true, raw: true]
    test "returns proper noreply", ctx do
      state = Should.Be.NoReply.with_state(ctx.state)

      want_kv = [alfred: AlfredSim, equipment: ctx.equipment]
      Should.Be.Struct.with_all_key_value(state, State, want_kv)
    end
  end

  describe "Carol.Server.handle_continue/2 :programs" do
    @tag equipment_add: [cmd: "off"], program_add: :live_programs
    @tag state_add: [bootstrap: true]
    @tag handle_add: [continue: :programs]
    test "executes a cmd when a program is live", ctx do
      %State{exec_result: er, cmd_live: cmd_live} = ctx.new_state

      Should.Be.Struct.with_all_key_value(er, ExecResult, cmd: "on")
      Should.Be.equal(cmd_live, "on")

      assert_cmd_echoed(ctx, "on")
    end

    @tag equipment_add: [cmd: "on"], program_add: :future_programs
    @tag state_add: [bootstrap: true]
    @tag handle_add: [continue: :programs]
    test "executes a cmd 'off' when all programs are in the future", ctx do
      %State{exec_result: er, cmd_live: cmd_live} = ctx.new_state

      Should.Be.Struct.with_all_key_value(er, ExecResult, cmd: "off")
      Should.Be.equal(cmd_live, "off")

      assert_cmd_echoed(ctx, "off")
    end

    @tag equipment_add: [cmd: "on"], program_add: :live_quick_programs
    @tag state_add: [bootstrap: true]
    @tag handle_add: [continue: :programs]
    test "keeps previous cmd when next cmd will start within 1000ms", ctx do
      ctx.new_state
      |> Should.Be.Struct.with_all_key_value(State, exec_result: :keep)
    end
  end

  describe "Carol.Server.handle_info/2 handles Alfred" do
    @tag equipment_add: [cmd: "oof"], program_add: :live_programs
    @tag state_add: [bootstrap: true], memo_add: [missing?: true]
    @tag handle_add: [func: &Server.handle_info/2, msg: :notify_msg]
    test "TrackerEntry with matching refid", ctx do
      ctx.new_state
      |> Should.Be.Struct.with_key(State, :notify_at)
      |> Should.Be.DateTime.greater(ctx.memo_before_dt)
    end
  end

  describe "Carol.Server.handle_info/2 handles Broom" do
    # NOTE: no longer needed, :programs and :playlist are calculated in bootstrap

    @tag equipment_add: [cmd: "on", rc: :pending], program_add: :live_programs
    @tag state_add: [bootstrap: true]
    test "TrackerEntry with matching refid", ctx do
      new_state =
        Server.handle_continue(:programs, ctx.state)
        |> Should.Be.NoReply.with_state()

      %State{exec_result: er} = new_state
      te = %Broom.TrackerEntry{cmd: er.cmd, refid: er.refid}

      Server.handle_info({Broom, te}, new_state)
      |> Should.Be.NoReply.with_state()
      |> Should.Be.Struct.with_key(State, :cmd_live)
      |> Should.Contain.binaries(["PENDING", "on"])
    end
  end

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
  defp opts_add(ctx), do: Carol.OptsAid.add(ctx)
  defp program_add(ctx), do: Carol.ProgramAid.add(ctx)
  defp start_args_add(ctx), do: Carol.StartArgsAid.add(ctx)
  defp state_add(ctx), do: Carol.StateAid.add(ctx)
end
