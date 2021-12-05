defmodule IlluminationServerTest do
  use ExUnit.Case, async: true
  use Should

  alias Alfred.ExecCmd

  alias Illumination.Schedule.Result
  alias Illumination.{Server, State}

  @moduletag illumination: true, illumination_server: true

  setup_all do
    {:ok, %{alfred: AlfredSim, server_name: __MODULE__}}
  end

  setup [:equipment_add, :schedule_add, :state_add, :memo_add, :start_args_add]

  describe "Illumination.Server starts supervised" do
    @tag equipment_add: [], start_args_add: []
    test "without schedules", ctx do
      ctx.start_args
      |> Server.child_spec()
      |> then(fn spec -> start_supervised(Server, spec) end)
      |> Should.Be.Ok.tuple_with_pid()
      |> Should.Be.Server.with_state()
      |> Should.Contain.kv_pairs(server_name: ctx.server_name, result: nil, schedules: [])
    end

    @tag equipment_add: [], schedule_add: [:typical], start_args_add: [:schedules]
    test "with schedules", ctx do
      start_supervised({Server, ctx.start_args})
      |> Should.Be.Ok.tuple_with_pid()
      |> Should.Be.Server.with_state()
      |> Should.Contain.kv_pairs(server_name: ctx.server_name, result: nil)
    end
  end

  describe "Illumination.Server.handle_call/3" do
    @tag equipment_add: [cmd: "off"], schedule_add: [:typical]
    @tag state_add: [schedule: true]
    test "processes :restart message", ctx do
      Server.handle_call(:restart, self(), ctx.state)
      |> Should.Be.Reply.stop_normal(:restarting)
    end
  end

  describe "Illumination.Server.call/2" do
    @tag equipment_add: [], schedule_add: [:typical], start_args_add: [:schedules]
    test "calls server with message", ctx do
      start_supervised({Server, ctx.start_args})
      |> Should.Be.Ok.tuple_with_pid()
      |> Should.Be.Server.with_state()
      |> Should.Contain.kv_pairs(server_name: ctx.server_name, result: nil)

      Server.call(:restart, ctx.server_name)
      |> Should.Be.equal(:restarting)
    end
  end

  describe "Illumination.Server.handle_continue/2" do
    @tag equipment_add: [], schedule_add: [:typical]
    @tag state_add: [bootstrap: true, raw: true]
    test "returns proper noreply", ctx do
      state = Should.Be.NoReply.with_state(ctx.state)

      want_kv = [alfred: AlfredSim, equipment: ctx.equipment]
      Should.Be.Struct.with_all_key_value(state, State, want_kv)
    end
  end

  describe "Illumination.Server.handle_info/2 handles" do
    @tag equipment_add: [cmd: "on"], schedule_add: [:typical]
    @tag state_add: [bootstrap: true], memo_add: []
    test "first Memo", ctx do
      new_state =
        Illumination.Server.handle_info(ctx.notify_msg, ctx.state)
        |> Should.Be.NoReply.with_state()

      Should.Be.struct(new_state.result, Result)
      Should.Be.DateTime.greater(new_state.last_notify_at, ctx.memo_before_dt)

      Should.Be.equal(new_state.result.action, :queued)

      receive do
        {:echo, %ExecCmd{}} -> assert true
        error -> refute true, Should.msg(error, "should have received ExecCmd")
      after
        100 -> refute true, "should have received the ExecCmd"
      end
    end

    @tag equipment_add: [cmd: "off"], schedule_add: [:typical]
    @tag state_add: [schedule: true], memo_add: []
    test "Memo matching equipment status", ctx do
      new_state =
        Illumination.Server.handle_info(ctx.notify_msg, ctx.state)
        |> Should.Be.NoReply.with_state()

      Should.Be.DateTime.greater(new_state.last_notify_at, ctx.memo_before_dt)
    end

    @tag equipment_add: [rc: :pending], schedule_add: [:typical]
    @tag state_add: [schedule: true], memo_add: []
    test "Memo when equipment is pending", ctx do
      Illumination.Server.handle_info(ctx.notify_msg, ctx.state)
      |> Should.Be.NoReply.with_state()
    end

    @tag equipment_add: [rc: :pending], schedule_add: [:typical]
    @tag state_add: [schedule: true], memo_add: [missing?: true]
    test "Memo when equipment is missing", ctx do
      new_state =
        Illumination.Server.handle_info(ctx.notify_msg, ctx.state)
        |> Should.Be.NoReply.with_state()

      Should.Be.DateTime.greater(new_state.last_notify_at, ctx.memo_before_dt)
    end

    @tag capture_log: true
    @tag equipment_add: [cmd: "on"], schedule_add: [:typical]
    @tag state_add: [schedule: true], memo_add: []
    test "Memo when cmd is mismatched", ctx do
      Illumination.Server.handle_info(ctx.notify_msg, ctx.state)
      |> Should.Be.NoReply.stop(:normal)
    end

    # @tag equipment_add: [cmd: "on"], schedule_add: [:typical]
    # @tag state_add: [schedule: true], memo_add: []
    # test "TrackerEntry with matching reference", ctx do
    #   broom_msg = {Broom, }
    #
    #   Illumination.Server.handle_info(ctx.notify_msg, ctx.state)
    #   |> Should.Be.NoReply.stop(:normal)
    # end
  end

  def equipment_add(ctx), do: Alfred.NamesAid.equipment_add(ctx)
  def memo_add(ctx), do: Alfred.NotifyAid.memo_add(ctx)
  def schedule_add(ctx), do: Illumination.ScheduleAid.add(ctx)
  def state_add(ctx), do: Illumination.StateAid.add(ctx)

  def start_args_add(%{start_args_add: opts} = ctx) when is_list(opts) do
    want_keys = opts ++ [:alfred, :equipment]

    Map.take(ctx, want_keys)
    |> Enum.into([])
    |> Keyword.merge(id: ctx.server_name)
    |> then(fn start_args -> %{start_args: start_args} end)
  end

  def start_args_add(_), do: :ok
end
