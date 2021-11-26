defmodule Rena.HoldCmd.ServerTest do
  use ExUnit.Case
  use Should

  @moduletag rena: true, rena_holdcmd_server: true

  alias Alfred.{ExecCmd, ExecResult}
  alias Alfred.NamesAid
  alias Alfred.Notify.{Memo, Ticket}
  alias Rena.HoldCmd.{Server, ServerTest, State}

  @equipment_default [type: :mut, rc: :ok, cmd: "off"]

  setup_all do
    # base ctx
    alfred = Rena.Alfred
    server_name = ServerTest
    start_args = [id: ServerTest]
    base = %{alfred: alfred, server_name: server_name, start_args: start_args}

    # default setup options
    setup = %{start_args_add: []}

    # default ctx
    ctx = base |> Map.merge(setup)
    {:ok, ctx}
  end

  setup [:equipment_add, :start_args_add, :server_add, :state_add]

  # NOTE:  only two tests are required for starting supervised because
  #        once started no code is executed until receipt of a notify
  describe "Rena.HoldCmd.Server starts supervised" do
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

  describe "Rena.HoldCmd.Server.handle_call/3" do
    @tag state_add: [alfred: Alfred]
    test "processes :pause message", %{state: state} do
      reply = Server.handle_call(:pause, self(), state)

      new_state = Should.Be.Tuple.reply_ok_with_struct(reply, State)

      Should.Be.Struct.with_all_key_value(new_state, State, ticket: :paused)
    end

    @tag state_add: [alfred: Alfred]
    test "processes :resume message", %{state: state} do
      reply = Server.handle_call(:resume, self(), state)

      new_state = Should.Be.Tuple.reply_ok_with_struct(reply, State)
      Should.Be.Struct.with_key_struct(new_state, State, :ticket, Ticket)
    end
  end

  describe "Rena.HoldCmd.Server.handle_info/2" do
    @tag equipment_add: [type: :mut, rc: :missing], state_add: []
    test "processes a :notify message when equipment is missing", ctx do
      state = ctx.state

      want_kv = [last_notify_at: :none]
      Should.Be.Struct.with_all_key_value(state, State, want_kv)

      memo = %Memo{name: ctx.equipment, missing?: true}

      Server.handle_info({:notify, memo}, state)
      |> Should.Be.Tuple.noreply_with_struct(State)
      |> Should.Be.Struct.with_all_key_value(State, last_exec: :none)
      |> Should.Be.Struct.with_key_struct(State, :last_notify_at, DateTime)
    end

    @tag equipment_add: [type: :mut, rc: :ok, cmd: "on"]
    @tag hold_cmd: %ExecCmd{cmd: "on"}
    @tag state_add: []
    test "processes a :notify message when status matches hold cmd", ctx do
      state = ctx.state

      want_kv = [last_notify_at: :none, last_exec: :none]
      Should.Be.Struct.with_all_key_value(state, State, want_kv)

      memo = %Memo{name: ctx.equipment, missing?: false}

      Server.handle_info({:notify, memo}, state)
      |> Should.Be.Tuple.noreply_with_struct(State)
      |> Should.Be.Struct.with_all_key_value(State, last_exec: :no_change)
      |> Should.Be.Struct.with_key_struct(State, :last_notify_at, DateTime)
    end

    @tag equipment_add: [type: :mut, rc: :pending, cmd: "off"]
    @tag hold_cmd: %ExecCmd{cmd: "on", cmd_opts: [echo: true]}
    @tag state_add: []
    test "processes a :notify message when status does not match hold cmd", ctx do
      state = ctx.state

      want_kv = [last_notify_at: :none, last_exec: :none]
      Should.Be.Struct.with_all_key_value(state, State, want_kv)

      memo = %Memo{name: ctx.equipment, missing?: false}

      new_state =
        Server.handle_info({:notify, memo}, state)
        |> Should.Be.Tuple.noreply_with_struct(State)

      # verify the ExecCmd resulted in an actual command
      Should.Be.Struct.with_key_struct(new_state, State, :last_exec, ExecResult)
      |> Should.Be.Struct.with_key(ExecResult, :refid)
      |> Should.Be.binary()

      # ensure Alfred.execute/2 was invoked
      receive do
        {:echo, %ExecCmd{}} -> assert true == true
      after
        1000 -> assert :echoed == true, Should.msg(:echoed, "ExecCmd should be echoed")
      end
    end
  end

  def equipment_add(ctx) do
    case ctx do
      %{equipment_add: opts} ->
        # add [key: :equipment] so NamesAid returns the proper map to merge into ctx
        opts = Keyword.put_new(opts, :key, :equipment)

        NamesAid.make_name(%{make_name: opts})

      # when equipment add is not present add the default equipment
      _ ->
        %{equipment_add: @equipment_default} |> equipment_add()
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

  def start_args_add(ctx) do
    case ctx do
      %{start_args_add: false} -> :ok
      %{start_args_add: opts} -> %{start_args: assemble_start_args(ctx, opts)}
      _ -> :ok
    end
  end

  def state_add(%{state_add: opts} = ctx) when is_list(opts) do
    start_args = assemble_start_args(ctx, opts)
    %{start: {_, _, [args]}} = Server.child_spec(start_args)

    init_reply = Server.init(args)
    {:ok, state, _} = Should.Be.Tuple.with_size(init_reply, 3)
    Should.Be.struct(state, State)

    state = Server.handle_continue(:bootstrap, state) |> Should.Be.Tuple.with_rc(:noreply)

    Should.Be.struct(state, State)

    %{state: state}
  end

  def state_add(_), do: :ok

  @start_args_keys [:alfred, :equipment, :hold_cmd, :known_name]
  defp assemble_start_args(ctx, opts) do
    from_ctx = Map.take(ctx, @start_args_keys) |> Enum.into([])

    for {k, v} <- ctx.start_args ++ from_ctx, reduce: opts do
      acc -> Keyword.put_new(acc, k, v)
    end
  end
end
