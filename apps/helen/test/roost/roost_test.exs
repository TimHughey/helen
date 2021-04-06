defmodule RoostServerTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Roost.Server

  setup_all do
    for {pwm_dev, pwm_alias} <- [
          {"pwm/roost-alpha.pin:1", "roost disco ball"},
          {"pwm/roost-alpha.pin:3", "roost el wire"},
          {"pwm/roost-alpha.pin:2", "roost el wire entry"},
          {"pwm/roost-beta.pin:2", "roost led forest"},
          {"pwm/roost-beta.pin:1", "roost lights sound one"},
          {"pwm/roost-gamma.pin:1", "roost lights sound three"}
        ],
        reduce: %{pwm_alias_create: []} do
      acc ->
        update_in(acc, [:pwm_alias_create], fn x ->
          List.flatten([x, PulseWidth.alias_create(pwm_dev, pwm_alias)])
        end)
    end
  end

  setup context do
    {:ok, _pid} = Roost.restart()
    context
  end

  @tag :skip
  test "roost server creates the server state via init/1" do
    {rc, state, continue} = Server.init([])

    assert rc == :ok
    assert continue == {:continue, :bootstrap}
    assert is_map(state)
    assert %{token: _, token_at: _} = state
    assert %{module: Roost.Server} = state
    assert %{base: _, workers: _, modes: _} = state[:opts]
  end

  @tag :skip
  test "can get Roost available modes" do
    modes = Roost.available_modes()
    assert is_list(modes)
    assert modes == [:all_stop, :closed, :dance_with_me, :leaving]
  end

  @tag :skip
  test "roost server ignores logic cast messages when msg token != state token" do
    msg = %{token: make_ref()}
    {:ok, state, _continue} = Server.init([])

    assert {:noreply, %{token: _}, _timeout} =
             Server.handle_cast({:logic, msg}, state)
  end

  @tag :skip
  test "roost server ignores logic info messages when the token != state token" do
    msg = %{token: make_ref()}
    {:ok, state, _} = Server.init([])

    assert {:noreply, %{token: _}, _timeout} =
             Server.handle_info({:logic, msg}, state)
  end

  @tag :skip
  test "roost server can be set to all stop" do
    assert {:ok, :all_stop} == Server.change_mode(:all_stop)

    assert :all_stop == Server.active_mode()
    assert Server.holding?()
  end

  @tag :skip
  test "roost server can change modes" do
    assert {:ok, :dance_with_me} == Roost.mode(:dance_with_me)
  end

  @tag :skip
  test "the truth will set you free" do
    assert true
  end
end
