defmodule LightsServerTest do
  use Timex
  use ExUnit.Case, async: true

  @moduletag :server

  import GardenTestHelpers, only: [cfg_toml_file: 1, make_state: 1, pretty: 1]

  def setup_ctx(args) do
    {rc, s} = make_state(args)

    assert :ok == rc, "state creation failed#{pretty(s)}"

    on_exit(fn -> GardenTestHelpers.reset_data_file_permissions() end)

    %{mod: s.mod, state: s, server_name: s.name}
  end

  setup ctx do
    args = get_in(ctx, [:state_args]) || :default

    {:ok, setup_ctx(args)}
  end

  test "can the server handle unmatched call message", %{mod: mod, state: state} do
    # implict log test
    {rc, reply, s, _timeout} = mod.handle_call(:nomatch, nil, state)

    assert rc == :reply
    assert reply == {:bad_call, :nomatch}
    assert Map.equal?(state, s)
  end

  test "can the server handle unmatched cast message", %{mod: mod, state: state} do
    # implict log test

    {rc, s, _timeout} = mod.handle_cast(:nomatch, state)

    assert rc == :noreply
    assert Map.equal?(state, s)
  end

  test "can the server handle terminate callback", %{mod: mod, state: state} do
    assert :ok == mod.terminate(:ill_be_back, state)
  end

  @tag cfg_file: cfg_toml_file(:unreadable)
  test "can the server detect unreadable config file", %{mod: mod, state: s, cfg_file: cf} do
    {rc, fstat} = File.stat(cf)
    assert :ok == rc, "unable to stat#{pretty(cf)}"

    rc = File.chmod(cf, 0o000)

    assert :ok == rc, "unable to chmod(0o000)#{pretty(cf)}"

    # change the config file to something unreadable
    args = s.args |> update_in([:cfg_file], fn _x -> cf end)
    s = put_in(s, [:args], args)

    {rc, s, c} = mod.handle_continue(:load_cfg, s)

    assert :noreply == rc, "handle_continue/2 should return :noreply"
    assert {:continue, :run} == c, "handle_continue/2 should return {:continue, :run}"
    assert is_map_key(s, :invalid), "state should contain :invalid#{pretty(s)}"

    rc = File.chmod(cf, fstat.mode)
    assert :ok == rc, "unable to chmod(#{inspect(fstat.mode)})#{pretty(cf)}"
  end

  test "can the server start", %{mod: mod} do
    wait_for_start = fn ->
      for _i <- 1..1000, reduce: false do
        false ->
          Process.sleep(1)
          mod.alive?()

        true ->
          true
      end
    end

    assert wait_for_start.()
  end

  test "can server handle :timeout info messages", %{mod: mod, state: s} do
    {rc, s, _timeout} = mod.handle_info(:timeout, s)

    assert rc == :noreply, "handle_info(:timeout, s) should return :noreply"

    timeout = get_in(s, [:timeout])
    fail = "state should have :timeout%{}#{pretty(s)}"
    assert is_map(timeout), fail

    fail = "last should be a %DateTime{}#{pretty(s)}"
    assert %DateTime{} = get_in(timeout, [:last]), fail

    count = get_in(timeout, [:count])
    fail = "count should not be nil#{pretty(s)}"
    refute is_nil(count), fail

    fail = "count should be > 0#{pretty(s)}"
    assert count > 0, fail
  end

  test "can server handle :run info messages", %{mod: mod, state: s} do
    {rc, s, _timeout} = mod.handle_info(:run, s)

    assert rc == :noreply, "handle_info(:timeout, s) should return :noreply"

    timeout = get_in(s, [:run])
    fail = "state should have :run%{}#{pretty(s)}"
    assert is_map(timeout), fail

    fail = "last should be a %DateTime{}#{pretty(s)}"
    assert %DateTime{} = get_in(timeout, [:last]), fail

    count = get_in(timeout, [:count])
    fail = "count should not be nil#{pretty(s)}"
    refute is_nil(count), fail

    fail = "count should be > 0#{pretty(s)}"
    assert count > 0, fail
  end
end
