defmodule Rena.SetPt.ServerTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag rena: true, rena_setpt_server: true

  alias Alfred.ExecResult
  alias Alfred.Notify.{Memo, Ticket}
  alias Broom.TrackerEntry
  alias Rena.Sensor
  alias Rena.SetPt.{Server, ServerTest, State}

  import Alfred.NamesAid, only: [equipment_add: 1, sensors_add: 1]
  import Rena.StartArgsAid, only: [start_args_add: 1]

  setup_all do
    # base ctx
    alfred = AlfredSim
    server_name = ServerTest
    start_args = [id: ServerTest]
    base = %{alfred: alfred, server_name: server_name, start_args: start_args}

    # default setup options
    setup = %{start_args_add: []}

    # default ctx
    ctx = Map.merge(base, setup)
    {:ok, ctx}
  end

  setup [:equipment_add, :sensors_add, :start_args_add, :server_add, :state_add]

  # NOTE:  only two tests are required for starting supervised because
  #        once started no code is executed until receipt of a notify
  describe "Rena.SetPt.Server starts supervised" do
    test "fails when init args missing :server_name" do
      child_spec = %{id: ServerTest, start: {Server, :start_link, [[]]}, restart: :transient}
      start_supervised(child_spec) |> Should.Be.Tuple.with_rc(:error)
    end

    @tag server_add: []
    test "when init args contains :server_name", ctx do
      Should.Be.Map.with_key(ctx, :server_pid)

      state = :sys.get_state(ctx.server_name) |> Should.Be.struct(State)

      Should.Be.binary(state.equipment)
      Should.Be.struct(state.ticket, Ticket)
    end
  end

  describe "Rena.Server.server.handle_call/3" do
    test "accepts :pause messages" do
    end
  end

  describe "Rena.SetPt.Server.handle_info/2 processes Notify" do
    @tag equipment_add: [], state_add: []
    test "missing messages", %{state: state} do
      res = Server.handle_info({Alfred, %Memo{name: state.equipment, missing?: true}}, state)

      should_be_noreply_tuple_with_state(res, State)
    end

    @tag equipment_add: [], state_add: []
    test "normal messages", %{state: state} do
      res = Server.handle_info({Alfred, %Memo{name: state.equipment, missing?: false}}, state)

      should_be_noreply_tuple_with_state(res, State)
    end
  end

  describe "Rena.SetPt.Server.handle_info/2 processes TrackerEntry" do
    @tag equipment_add: [], state_add: []
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

    @tag equipment_add: [], state_add: []
    test "when TrackerEntry is not acked and Last Exec refids match", %{state: state} do
      refid = "123456"
      te = %TrackerEntry{refid: refid, acked: false}
      er = %ExecResult{refid: refid}

      res = Server.handle_info({Broom, te}, %State{state | last_exec: er})
      should_be_noreply_tuple_with_state(res, State)

      {:noreply, new_state} = res

      should_be_equal(new_state.last_exec, :failed)
    end

    @tag equipment_add: [], state_add: []
    test "when TrackerEntry refid does not match Exec refid", %{state: state} do
      te = %TrackerEntry{refid: "123456", acked: true}
      er = %ExecResult{refid: "7890"}

      res = Server.handle_info({Broom, te}, %State{state | last_exec: er})
      should_be_noreply_tuple_with_state(res, State)

      {:noreply, new_state} = res

      should_be_equal(new_state.last_exec, :failed)
    end

    @tag equipment_add: [], state_add: []
    @tag capture_log: true
    test "when State last_exec is not an ExecResult", %{state: state} do
      te = %TrackerEntry{refid: "123456", acked: true}

      res = Server.handle_info({Broom, te}, state)
      should_be_noreply_tuple_with_state(res, State)

      {:noreply, new_state} = res

      should_be_equal(new_state.last_exec, :none)
    end
  end

  def server_add(ctx) do
    case ctx do
      %{server_add: false} ->
        :ok

      %{server_add: [], start_args: start_args} ->
        pid = start_supervised({Server, start_args}) |> Should.Be.Ok.tuple_with_pid()

        %{server_pid: Should.Be.alive(pid)}

      _ ->
        :ok
    end
  end

  @sensors_opts for temp_f <- [11.0, 11.1, 11.2, 6.2], do: [temp_f: temp_f]
  def state_add(%{state_add: opts} = ctx) do
    fields = [
      alfred: AlfredSim,
      server_name: ServerTest,
      equipment: ctx.equipment,
      sensors: %{sensors_add: @sensors_opts} |> sensors_add() |> Map.get(:sensors),
      sensor_range: opts[:range] || %Sensor.Range{low: 1.0, high: 11.0, unit: :temp_f},
      last_exec: opts[:last_exec] || :none
    ]

    %{state: struct(State, fields)}
  end

  def state_add(_), do: :ok
end
