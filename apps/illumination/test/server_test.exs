defmodule IlluminationServerTest do
  use ExUnit.Case, async: true
  use Should

  test "Illuminaton.child_spec/2 creates correct spec map" do
    spec = Illumination.RefImpl.child_spec(config: true)

    should_contain(spec, [{:id, Illumination.RefImpl}])
    should_contain(spec, [{:restart, :transient}])
    should_contain(spec, [{:shutdown, 10_000}])
    should_contain_key(spec, :start)
    should_be_tuple(spec.start)
    assert tuple_size(spec.start) == 3, "?start should be tuple with 3 elements"

    {server_module, func, init_args} = spec.start
    should_be_equal(server_module, Illumination.Server)
    should_be_equal(func, :start_link)

    init_args = List.flatten(init_args)
    should_be_non_empty_list(init_args)

    should_contain(init_args, [{:use_opts, []}])
    should_contain(init_args, [{:module, Illumination.RefImpl}])
    should_contain(init_args, [{:start_args, [config: true]}])
  end

  test "Illumination.Server starts supervised without equipment or schedules" do
    start_args = [alfred: AlfredNotFound, equipment: "test_equip"]
    start_res = start_supervised({Illumination.RefImpl, start_args})

    should_be_ok_pid(start_res)

    state = :sys.get_state(Illumination.RefImpl)
    should_be_struct(state, Illumination.State)
    should_be_equal(state.alfred, AlfredNotFound)

    stop_res = stop_supervised(Illumination.RefImpl)
    should_be_equal(stop_res, :ok)
  end

  test "Illumination.Server starts supervised with equipment and schedules" do
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

    start_args = [alfred: AlfredFound, equipment: "test_equip", schedules: schedules]
    start_res = start_supervised({Illumination.RefImpl, start_args})

    should_be_ok_pid(start_res)

    state = :sys.get_state(Illumination.RefImpl)
    should_be_struct(state, Illumination.State)
    should_be_equal(state.alfred, AlfredFound)
    should_be_struct(state.result, Illumination.Schedule.Result)
    should_be_struct(state.result.schedule, Illumination.Schedule)

    stop_res = stop_supervised(Illumination.RefImpl)
    should_be_equal(stop_res, :ok)
  end

  test "Illumination.Server finds equipment" do
    start_args = [alfred: AlfredFound, equipment: "test_equip"]
    {:ok, state, _} = Illumination.Server.init(start_args)

    should_be_struct(state, Illumination.State)

    res = Illumination.Server.handle_info(:find_equipment, state)
    should_be_tuple(res)
    should_be_tuple_with_size(res, 3)

    {noreply, new_state, continue} = res
    should_be_equal(noreply, :noreply)
    should_be_struct(new_state, Illumination.State)
    should_be_struct(new_state.equipment, Alfred.NotifyTo)
    should_be_equal(continue, {:continue, :first_schedule})

    res = Illumination.Server.handle_continue(:first_schedule, new_state)
    should_be_noreply_tuple_with_state(res, Illumination.State)

    state = elem(res, 1)
    should_be_struct(state, Illumination.State)
  end
end
