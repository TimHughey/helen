defmodule ReefFirstMateTest do
  @moduledoc false

  use ExUnit.Case

  alias Helen.Config.Parser
  alias Reef.FirstMate.Server, as: FirstMate

  @lib_path Path.join([__DIR__, "..", "..", "lib"]) |> Path.expand()
  @config_path Path.join([@lib_path, "reef", "first_mate", "opts"])
  @config_file Path.join([@config_path, "defaults.txt"])
  @config_txt File.read!(@config_file)

  setup_all do
    %{}
  end

  test "reef FirstMate creates the server state via init/1" do
    {rc, state, continue} = FirstMate.init([])

    assert rc == :ok
    assert continue == {:continue, :bootstrap}
    assert is_map(state)
    assert %{token: _, token_at: _} = state
    assert %{module: FirstMate} = state
    assert %{base: _, workers: _, modes: _} = state[:opts]
  end

  test "can parse default config" do
    state = Parser.parse(@config_txt)

    assert is_map(state[:parser])
    assert Parser.syntax_ok?(state)
  end

  test "can get FirstMate available modes" do
    modes = FirstMate.available_modes()
    assert is_list(modes)

    assert modes == [
             :all_stop,
             :clean,
             :normal_operations,
             :water_change
           ]
  end

  test "reef FirstMate ignores logic cast messages when msg token != state token" do
    msg = %{token: make_ref()}
    {:ok, state, _continue} = FirstMate.init([])

    assert {:noreply, %{token: _}, _timeout} =
             FirstMate.handle_cast({:logic, msg}, state)
  end

  test "roost server ignores logic info messages when the token != state token" do
    msg = %{token: make_ref()}
    {:ok, state, _} = FirstMate.init([])

    assert {:noreply, %{token: _}, _timeout} =
             FirstMate.handle_info({:logic, msg}, state)
  end

  test "the truth will set you free" do
    assert true
  end
end
