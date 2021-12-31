defmodule Rena.SetPt.ServerTest do
  use ExUnit.Case, async: true

  @moduletag rena: true, rena_setpt_server: true

  alias Alfred.ExecResult
  alias Alfred.Notify.{Memo}
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
      assert {:error, _} = start_supervised(child_spec)
    end

    @tag server_add: []
    test "when init args contains :server_name", ctx do
      assert %{server_pid: server_pid, server_name: server_name} = ctx
      assert Process.alive?(server_pid)

      assert %Rena.SetPt.State{equipment: <<_::binary>>, ticket: %Alfred.Notify.Ticket{}} =
               :sys.get_state(server_name)
    end
  end

  describe "Rena.Server.server.handle_call/3" do
    test "accepts :pause messages" do
    end
  end

  describe "Rena.SetPt.Server.handle_info/2 processes Notify" do
    @tag equipment_add: [], state_add: []
    test "missing messages", %{state: state} do
      assert {:noreply, %Rena.SetPt.State{}} =
               Server.handle_info({Alfred, %Memo{name: state.equipment, missing?: true}}, state)
    end

    @tag equipment_add: [], state_add: []
    test "normal messages", %{state: state} do
      assert {:noreply, %Rena.SetPt.State{}} =
               Server.handle_info({Alfred, %Memo{name: state.equipment, missing?: false}}, state)
    end
  end

  describe "Rena.SetPt.Server.handle_info/2 processes TrackerEntry" do
    @tag equipment_add: [], state_add: []
    test "when TrackerEntry acked and Last Exec refids match", %{state: state} do
      refid = "123456"
      acked_at = DateTime.utc_now()
      te = %TrackerEntry{refid: refid, acked: true, acked_at: acked_at}
      er = %ExecResult{refid: refid}

      assert {:noreply, %Rena.SetPt.State{last_exec: ^acked_at}} =
               Server.handle_info({Broom, te}, %State{state | last_exec: er})
    end

    @tag equipment_add: [], state_add: []
    test "when TrackerEntry is not acked and Last Exec refids match", %{state: state} do
      refid = "123456"
      te = %TrackerEntry{refid: refid, acked: false}
      er = %ExecResult{refid: refid}

      assert {:noreply, %Rena.SetPt.State{last_exec: :failed}} =
               Server.handle_info({Broom, te}, %State{state | last_exec: er})
    end

    @tag equipment_add: [], state_add: []
    test "when TrackerEntry refid does not match Exec refid", %{state: state} do
      te = %TrackerEntry{refid: "123456", acked: true}
      er = %ExecResult{refid: "7890"}

      assert {:noreply, %Rena.SetPt.State{last_exec: :failed}} =
               Server.handle_info({Broom, te}, %State{state | last_exec: er})
    end

    @tag equipment_add: [], state_add: []
    @tag capture_log: true
    test "when State last_exec is not an ExecResult", %{state: state} do
      te = %TrackerEntry{refid: "123456", acked: true}

      assert {:noreply, %Rena.SetPt.State{last_exec: :none}} = Server.handle_info({Broom, te}, state)
    end
  end

  def server_add(ctx) do
    case ctx do
      %{server_add: false} ->
        :ok

      %{server_add: [], start_args: start_args} ->
        assert {:ok, pid} = start_supervised({Server, start_args})

        assert Process.alive?(pid)

        %{server_pid: pid}

      _ ->
        :ok
    end
  end

  @sensors_opts for temp_f <- [11.0, 11.1, 11.2, 6.2], do: [temp_f: temp_f]
  def state_add(%{state_add: opts} = ctx) do
    [
      alfred: AlfredSim,
      server_name: ServerTest,
      equipment: ctx.equipment,
      sensors: %{sensors_add: @sensors_opts} |> sensors_add() |> Map.get(:sensors),
      sensor_range: opts[:range] || %Sensor.Range{low: 1.0, high: 11.0, unit: :temp_f},
      last_exec: opts[:last_exec] || :none
    ]
    |> then(fn fields -> %{state: struct(State, fields)} end)
  end

  def state_add(_), do: :ok
end
