defmodule ReefCaptainTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Reef.Captain.Server, as: Captain

  setup_all do
    %{}
  end

  setup context do
    restart_rc = Captain.restart()

    assert {rc, pid} = restart_rc
    assert rc == :ok
    assert is_pid(pid)

    context
  end

  test "reef Captain creates the server state via init/1" do
    {rc, state, continue} = Captain.init([])

    assert rc == :ok
    assert continue == {:continue, :bootstrap}
    assert is_map(state)
    assert %{token: _, token_at: _} = state
    assert %{module: Captain} = state
    assert %{base: _, workers: _, modes: _} = state[:opts]
  end

  test "can get Captain available modes" do
    modes = Captain.available_modes()
    assert is_list(modes)

    assert modes == [
             :add_salt,
             :all_stop,
             :dump_water,
             :fill,
             :final_check,
             :keep_fresh,
             :load_water,
             :match_conditions,
             :topoff
           ]
  end

  test "reef Captain ignores logic cast messages when msg token != state token" do
    msg = %{token: make_ref()}
    {:ok, state, _continue} = Captain.init([])

    assert {:noreply, %{token: _}, _timeout} =
             Captain.handle_cast({:logic, msg}, state)
  end

  test "reef Captain ignores logic info messages when the token != state token" do
    msg = %{token: make_ref()}
    {:ok, state, _} = Captain.init([])

    assert {:noreply, %{token: _}, _timeout} =
             Captain.handle_info({:logic, msg}, state)
  end

  test "can get overall reef Captain status" do
    status = Captain.status()

    assert is_map(status)

    assert %{
             name: "captain",
             status: status,
             active: %{mode: :none, step: :none, action: :none},
             modes: modes,
             ready: true,
             sub_workers: sub_workers
           } = status

    assert status in [:none, :initializing]
    assert is_list(modes)
    assert is_list(sub_workers)
  end

  test "reef Captain can be restarted, set to ready and standby" do
    res = Captain.server(:standby)

    assert res == {:ok, :standby}

    is_ready? = Captain.ready?()

    refute is_ready?
  end

  test "Captain prevents changing modes while server is in standby" do
    Captain.server(:standby)

    res = Captain.change_mode(:fill)

    assert {:fault, %{init: %{server: :standby}}} == res
  end

  @tag special: true
  test "Captain can be set to all stop" do
    assert {:ok, :all_stop} == Captain.change_mode(:all_stop)

    status = Captain.status()

    assert %{
             status: :holding,
             active: %{mode: :all_stop, step: :all_stop, action: _action},
             ready: true,
             modes: _modes,
             sub_workers: _workers
           } = status
  end

  # test "Captian can be set to all stop" do
  #   assert {:ok, :all_stop} == Captain.all_stop()
  # end

  test "the truth will set you free" do
    assert true
  end
end
