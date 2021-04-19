defmodule ReefFirstMateTest do
  @moduledoc false

  use ExUnit.Case

  alias Reef.FirstMate.Server, as: FirstMate

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

  test "can get FirstMate available modes" do
    modes = FirstMate.available_modes()
    assert is_list(modes)

    assert modes == [
             :all_stop,
             :clean,
             :heat_only,
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

  test "reef server ignores logic info messages when the token != state token" do
    msg = %{token: make_ref()}
    {:ok, state, _} = FirstMate.init([])

    assert {:noreply, %{token: _}, _timeout} =
             FirstMate.handle_info({:logic, msg}, state)
  end

  test "the truth will set you free" do
    assert true
  end
end
