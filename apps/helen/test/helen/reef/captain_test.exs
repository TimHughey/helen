defmodule ReefCaptainTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Helen.Config.Parser
  alias Reef.Captain.Server, as: Captain

  @lib_path Path.join([__DIR__, "..", "..", "..", "lib"]) |> Path.expand()
  @config_path Path.join([@lib_path, "reef", "captain", "opts"])
  @config_file Path.join([@config_path, "defaults.txt"])
  @config_txt File.read!(@config_file)

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

  test "can parse default config" do
    state = Parser.parse(@config_txt)

    assert is_map(state[:parser])
    assert Parser.syntax_ok?(state)
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
             :match_conditions
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

    assert status == %{status: :none, active: %{mode: :none, step: :none}}
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

    assert %{status: :holding, active: %{mode: :all_stop, step: :finally}} ==
             Captain.status()
  end

  # test "Captian can be set to all stop" do
  #   assert {:ok, :all_stop} == Captain.all_stop()
  # end

  test "the truth will set you free" do
    assert true
  end
end
