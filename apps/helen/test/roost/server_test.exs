defmodule RoostServerTest do
  @moduledoc false

  use ExUnit.Case

  alias Helen.Config.Parser
  alias Roost.Server

  @lib_path Path.join([__DIR__, "..", "..", "lib"]) |> Path.expand()
  @config_path Path.join([@lib_path, "roost", "opts"])
  @config_file Path.join([@config_path, "defaults.txt"])
  @config_txt File.read!(@config_file)

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

  test "roost server creates the server state via init/1" do
    {rc, state, continue} = Server.init([])

    assert rc == :ok
    assert continue == {:continue, :bootstrap}
    assert is_map(state)
    assert %{token: _, token_at: _} = state
    assert %{module: Roost.Server} = state
    assert %{base: _, workers: _, modes: _} = state[:opts]
  end

  test "can parse default config" do
    state = Parser.parse(@config_txt)

    assert is_map(state[:parser])
    assert Parser.syntax_ok?(state)
  end

  test "can get Roost available modes" do
    modes = Roost.available_modes()
    assert is_list(modes)
    assert modes == [:closed, :dance_with_me, :leaving]
  end

  test "roost server ignores logic cast messages when msg token != state token" do
    msg = %{token: make_ref()}
    {:ok, state, _continue} = Server.init([])

    assert {:noreply, %{token: _}, _timeout} =
             Server.handle_cast({:logic, msg}, state)
  end

  test "roost server ignores logic info messages when the token != state token" do
    msg = %{token: make_ref()}
    {:ok, state, _} = Server.init([])

    assert {:noreply, %{token: _}, _timeout} =
             Server.handle_info({:logic, msg}, state)
  end

  test "roost server can change modes" do
    {rc, mode} = Roost.mode(:dance_with_me)

    assert rc == :ok
    assert mode == :dance_with_me
  end

  test "the truth will set you free" do
    assert true
  end
end
