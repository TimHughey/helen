defmodule IlluminationServerTest do
  # NOTE: do not use async to avoid conflicts with starting supervised
  use ExUnit.Case
  use Should

  @moduletag illumination: true, illumination_server_test: true

  setup(:setup_basic_schedule)

  test "Illuminaton.child_spec/2 creates correct spec map" do
    spec = Illumination.RefImpl.child_spec(config: true)

    should_contain(spec, [{:id, Illumination.RefImpl}])
    should_contain(spec, [{:restart, :transient}])
    should_contain(spec, [{:shutdown, 10_000}])
    should_contain_key(spec, :start)
    should_be_tuple(spec.start)
    assert tuple_size(spec.start) == 3, "start should be tuple with 3 elements"

    {server_module, func, init_args} = spec.start
    should_be_equal(server_module, Illumination.Server)
    should_be_equal(func, :start_link)

    init_args = List.flatten(init_args)
    should_be_non_empty_list(init_args)

    should_contain(init_args, [{:use_opts, []}])
    should_contain(init_args, [{:module, Illumination.RefImpl}])
    should_contain(init_args, [{:start_args, [config: true]}])
  end

  test "Illumination.Server starts supervised without schedules" do
    start_args = [alfred: AlfredFound, equipment: "test_equip"]
    start_res = start_supervised({Illumination.RefImpl, start_args})

    should_be_ok_pid(start_res)

    state = :sys.get_state(Illumination.RefImpl)
    should_be_struct(state, Illumination.State)
    should_be_equal(state.alfred, AlfredFound)

    stop_res = stop_supervised(Illumination.RefImpl)
    should_be_equal(stop_res, :ok)
  end

  test "Illumination.Server can be queried for info and restarted" do
    start_args = [alfred: AlfredFound, equipment: "test_equip"]
    start_res = start_supervised({Illumination.RefImpl, start_args})

    should_be_ok_pid(start_res)

    info = Illumination.RefImpl.info()
    assert is_nil(info), "info should be nil"

    initial_pid = GenServer.whereis(Illumination.RefImpl)

    res = Illumination.RefImpl.restart()
    should_be_tuple_with_size(res, 2)
    {rc, restarting_pid} = res

    should_be_equal(rc, :restarting)
    should_be_equal(initial_pid, restarting_pid)

    stop_res = stop_supervised(Illumination.RefImpl)
    should_be_equal(stop_res, :ok)
  end

  @tag basic_schedule: true
  test "Illumination.Server starts supervised with equipment and schedules", %{
    schedules: schedules
  } do
    start_args = [alfred: AlfredFound, equipment: "test_equip", schedules: schedules]
    start_res = start_supervised({Illumination.RefImpl, start_args})

    should_be_ok_pid(start_res)

    state = :sys.get_state(Illumination.RefImpl)
    should_be_struct(state, Illumination.State)
    should_be_equal(state.alfred, AlfredFound)
    assert is_nil(state.result), "state result should be nil"

    stop_res = stop_supervised(Illumination.RefImpl)
    should_be_equal(stop_res, :ok)
  end

  @tag basic_schedule: true
  test "Illumination.Server handles first Alfred.NotifyMemo", %{schedules: schedules} do
    alias Alfred.{NotifyMemo, NotifyTo}
    alias Illumination.Schedule
    alias Illumination.Schedule.{Point, Result}
    alias Illumination.State

    start_at = DateTime.utc_now()

    equipment = "test_equipment"
    ref = make_ref()

    notify_to = %NotifyTo{name: equipment, ref: ref}

    initial_state = %State{
      alfred: AlfredSendExecMsg,
      equipment: notify_to,
      schedules: schedules,
      result: nil
    }

    reply = Illumination.Server.handle_continue(:bootstrap, initial_state)
    should_be_noreply_tuple_with_state(reply, State)

    {:noreply, state} = reply

    notify_memo = %NotifyMemo{ref: ref, name: equipment, missing?: false}
    notify_msg = {Alfred, notify_memo}

    reply = Illumination.Server.handle_info(notify_msg, state)

    should_be_noreply_tuple_with_state(reply, State)
    {:noreply, state} = reply

    assert DateTime.compare(state.last_notify_at, start_at) == :gt
    should_be_struct(state.result, Result)

    receive do
      %Alfred.ExecCmd{} -> assert true
      error -> refute true, "should have received ExecCmd:\n#{inspect(error, pretty: true)}"
    after
      100 -> refute true, "should have received the ExecCmd"
    end
  end

  test "Illumination.Server handles Alfred.NotifyMemo matching equipment status" do
    alias Alfred.{NotifyMemo, NotifyTo}
    alias Illumination.Schedule
    alias Illumination.Schedule.{Point, Result}
    alias Illumination.State

    equipment = "test_equipment"
    ref = make_ref()

    notify_to = %NotifyTo{name: equipment, ref: ref}

    state = %State{
      alfred: AlfredAlwaysOn,
      equipment: notify_to,
      result: %Result{schedule: %Schedule{start: %Point{cmd: "on"}}, action: :live}
    }

    notify_memo = %NotifyMemo{ref: ref, name: equipment, missing?: false}
    notify_msg = {Alfred, notify_memo}

    res = Illumination.Server.handle_info(notify_msg, state)

    should_be_noreply_tuple_with_state(res, State)
  end

  test "Illumination.Server handles Alfred.NotifyMemo when equipment cmd is pending" do
    alias Alfred.{NotifyMemo, NotifyTo}
    alias Illumination.Schedule
    alias Illumination.Schedule.{Point, Result}
    alias Illumination.State

    equipment = "test_equipment"
    ref = make_ref()

    notify_to = %NotifyTo{name: equipment, ref: ref}

    state = %State{
      alfred: AlfredAlwaysPending,
      equipment: notify_to,
      result: %Result{schedule: %Schedule{start: %Point{cmd: "on"}}, action: :live}
    }

    notify_memo = %NotifyMemo{ref: ref, name: equipment}
    notify_msg = {Alfred, notify_memo}

    res = Illumination.Server.handle_info(notify_msg, state)

    should_be_noreply_tuple_with_state(res, State)
  end

  def setup_basic_schedule(%{basic_schedule: true} = ctx) do
    alias Illumination.Schedule
    alias Illumination.Schedule.Point

    schedules = [
      %Schedule{
        id: "sunrise",
        start: %Point{sunref: "sunrise", cmd: "on"},
        finish: %Point{sunref: "sunrise", offset_ms: 300_000}
      },
      %Schedule{
        id: "sunset",
        start: %Point{sunref: "sunset", cmd: "on"},
        finish: %Point{sunref: "sunset", offset_ms: 300_000}
      }
    ]

    Map.put(ctx, :schedules, schedules)
  end

  def setup_basic_schedule(ctx), do: ctx
end
