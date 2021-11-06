defmodule Rena.SetPt.ServerTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag rena: true, rena_server: true

  alias Alfred.ExecResult
  alias Alfred.NotifyMemo, as: Memo
  alias Alfred.NotifyTo
  alias Broom.TrackerEntry
  alias Rena.Sensor
  alias Rena.SetPt.{Server, ServerTest, State}

  describe "Rena.SetPt.Server starts supervised" do
    setup [:setup_child_spec]

    test "with empty init args", %{child_spec: child_spec} do
      res = start_supervised(child_spec)

      pid = should_be_ok_tuple_with_pid(res)

      assert Process.alive?(pid)

      state = :sys.get_state(ServerTest)
      should_be_struct(state, State)
      should_be_struct(state.equipment, NotifyTo)

      res = stop_supervised(child_spec.id)
      should_be_equal(res, :ok)
    end
  end

  describe "Rena.SetPt.Server.handle_info/2 processes Notify" do
    setup [:setup_state]

    @tag state: []
    test "missing messages", %{state: state} do
      res = Server.handle_info({Alfred, %Memo{name: state.equipment, missing?: true}}, state)

      should_be_noreply_tuple_with_state(res, State)
    end

    @tag state: []
    test "normal messages", %{state: state} do
      res = Server.handle_info({Alfred, %Memo{name: state.equipment, missing?: false}}, state)

      should_be_noreply_tuple_with_state(res, State)
    end
  end

  describe "Rena.SetPt.Server.handle_info/2 processes TrackerEntry" do
    setup [:setup_state]

    @tag state: []
    test "when TrackerEntry acked and Last Exec refids match", %{state: state} do
      refid = "123456"
      acked_at = DateTime.utc_now()
      te = %TrackerEntry{refid: refid, acked: true, acked_at: acked_at}
      er = %ExecResult{refid: refid}

      res = Server.handle_info({Broom, te}, %State{state | last_exec: er})
      should_be_noreply_tuple_with_state(res, State)

      {:noreply, new_state} = res

      should_be_equal(new_state.last_exec, acked_at)
    end

    @tag state: []
    test "when TrackerEntry is not acked and Last Exec refids match", %{state: state} do
      refid = "123456"
      te = %TrackerEntry{refid: refid, acked: false}
      er = %ExecResult{refid: refid}

      res = Server.handle_info({Broom, te}, %State{state | last_exec: er})
      should_be_noreply_tuple_with_state(res, State)

      {:noreply, new_state} = res

      should_be_equal(new_state.last_exec, :failed)
    end

    @tag state: []
    test "when TrackerEntry refid does not match Exec refid", %{state: state} do
      te = %TrackerEntry{refid: "123456", acked: true}
      er = %ExecResult{refid: "7890"}

      res = Server.handle_info({Broom, te}, %State{state | last_exec: er})
      should_be_noreply_tuple_with_state(res, State)

      {:noreply, new_state} = res

      should_be_equal(new_state.last_exec, :failed)
    end

    @tag state: []
    @tag capture_log: true
    test "when State last_exec is not an ExecResult", %{state: state} do
      te = %TrackerEntry{refid: "123456", acked: true}

      res = Server.handle_info({Broom, te}, state)
      should_be_noreply_tuple_with_state(res, State)

      {:noreply, new_state} = res

      should_be_equal(new_state.last_exec, :none)
    end
  end

  def setup_child_spec(ctx) do
    id = ctx[:server_id] || __MODULE__
    server_name = ctx[:name] || ServerTest
    start_args = ctx[:start_args] || []

    args = [name: server_name] ++ start_args

    child_spec = %{id: id, start: {Server, :start_link, [args]}, restart: ctx[:restart] || :permanent}

    Map.put_new(ctx, :child_spec, child_spec)
  end

  def setup_state(%{state: opts} = ctx) do
    state = %State{
      alfred: Rena.Alfred,
      server_name: ServerTest,
      equipment: opts[:equipment] || "mutable good on",
      sensors: opts[:sensors] || ["mid 11.0", "mid 11.1", "mid 11.2", "mid 6.2"],
      sensor_range: opts[:range] || %Sensor.Range{low: 1.0, high: 11.0, unit: :temp_f},
      last_exec: opts[:last_exec] || :none
    }

    Map.put(ctx, :state, state)
  end
end
