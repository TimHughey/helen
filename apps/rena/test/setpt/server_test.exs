defmodule Rena.SetPt.ServerTest do
  use ExUnit.Case, async: true

  @moduletag rena: true, rena_setpt_server: true

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
    test "when init args contains :server_name, :equipment", ctx do
      assert %{server_pid: server_pid, server_name: server_name} = ctx
      assert Process.alive?(server_pid)

      assert %Rena.SetPt.State{equipment: <<_::binary>>, ticket: %Alfred.Ticket{}} =
               :sys.get_state(server_name)
    end
  end

  describe "Rena.Server.server.handle_call/3" do
    test "accepts :pause messages" do
    end
  end

  describe "Rena.SetPt.Server.handle_info/2 processes Alfred.Memo" do
    # NOTE: don't test missing?: true messages - they are not sent

    # NOTE: also tests deactivating equipment
    @tag equipment_add: [cmd: "on"], state_add: []
    test "normal messages", %{state: state} do
      assert {:noreply, %Rena.SetPt.State{last_exec: %Alfred.Execute{}}} =
               Server.handle_info({Alfred, %Alfred.Memo{name: state.equipment, missing?: false}}, state)
    end
  end

  describe "Rena.SetPt.Server.handle_info/2 processes Alfred.Track" do
    @tag equipment_add: [], state_add: []
    test "when Alfred.Track acked and Last Exec refids match", %{state: state} do
      acked_at = DateTime.utc_now()

      msg = {Alfred, %Alfred.Track{rc: :ok, at: %{released: acked_at}}}
      assert {:noreply, %Rena.SetPt.State{last_exec: ^acked_at}} = Server.handle_info(msg, state)
    end

    @tag equipment_add: [], state_add: []
    test "when Alfred.Track is not acked", %{state: state} do
      msg = {Alfred, %Alfred.Track{rc: :timeout}}
      assert {:noreply, %Rena.SetPt.State{last_exec: :failed}} = Server.handle_info(msg, state)
    end
  end

  def server_add(ctx) do
    case ctx do
      %{server_add: false} ->
        :ok

      %{server_add: [], start_args: start_args} ->
        %{equipment: name} = equipment_add(%{equipment_add: []})

        start_args = Keyword.put_new(start_args, :equipment, name)

        assert {:ok, pid} = start_supervised({Server, start_args})

        assert Process.alive?(pid)

        %{server_pid: pid}

      _ ->
        :ok
    end
  end

  @default_temp_f [11.0, 11.1, 11.2, 6.2]
  @sensors_opts Enum.map(@default_temp_f, fn temp_f -> [temp_f: temp_f] end)
  def state_add(%{state_add: opts} = ctx) do
    %{sensors: sensors} = Alfred.NamesAid.sensors_add(%{sensors_add: @sensors_opts})

    [
      alfred: AlfredSim,
      server_name: ServerTest,
      equipment: ctx.equipment,
      sensors: sensors,
      sensor_range: opts[:range] || %Sensor.Range{low: 1.0, high: 11.0, unit: :temp_f},
      last_exec: opts[:last_exec] || :none
    ]
    |> then(fn fields -> %{state: struct(State, fields)} end)
  end

  def state_add(_), do: :ok
end
