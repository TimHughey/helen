defmodule Rena.HoldCmd.ServerTest do
  use ExUnit.Case
  use Should

  @moduletag rena: true, rena_hold_cmd_server: true

  alias Alfred.ExecCmd
  alias Alfred.Notify.Ticket
  alias Rena.HoldCmd.{Server, ServerTest, State}

  describe "Rena.SetPt.Server starts supervised" do
    setup [:setup_child_spec]

    test "with empty init args", %{child_spec: child_spec} do
      res = start_supervised(child_spec)

      pid = should_be_ok_tuple_with_pid(res)

      assert Process.alive?(pid)

      state = :sys.get_state(ServerTest)
      should_be_struct(state, State)
      should_be_struct(state.equipment, Ticket)

      res = stop_supervised(child_spec.id)
      should_be_equal(res, :ok)
    end

    @tag start_args: [equipment: "foo", hold_cmd: %ExecCmd{cmd: "on"}]
    test "with arg list", %{child_spec: child_spec, start_args: start_args} do
      res = start_supervised(child_spec)

      pid = should_be_ok_tuple_with_pid(res)

      assert Process.alive?(pid)

      state = :sys.get_state(ServerTest)
      should_be_struct(state, State)
      should_be_struct(state.equipment, Ticket)
      should_be_equal(state.equipment.name, start_args[:equipment])
      should_be_struct(state.hold_cmd, ExecCmd)
      should_be_equal(state.hold_cmd.cmd, start_args[:hold_cmd].cmd)

      res = stop_supervised(child_spec.id)
      should_be_equal(res, :ok)
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
end
