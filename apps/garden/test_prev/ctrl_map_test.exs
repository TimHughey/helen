defmodule LightsControlMapTest do
  use ExUnit.Case, async: true
  import GardenTestHelpers, only: [make_state: 1, pretty: 1, cfg_toml_file: 1]

  @moduletag :control_map

  def find_job(ctrl_maps, job_name) do
    for %{job: x} = found when x == job_name <- ctrl_maps, reduce: %{} do
      %{} -> found
    end
  end

  def setup_ctx(args) do
    {rc, s} = make_state(args)

    assert :ok == rc, "state creation failed#{pretty(s)}"

    %{state: s, ctrl_maps: Lights.ControlMap.make_control_maps(s)}
  end

  setup ctx do
    args = get_in(ctx, [:state_args]) || :default

    {:ok, setup_ctx(args)}
  end

  test "can create a list of control maps", %{ctrl_maps: cm} = s do
    fail = "state should contain :ctrl_maps#{pretty(s)}"
    assert is_list(cm), fail
    refute cm == [], fail

    map = hd(cm)

    assert is_map_key(map, :start), "should have key :start#{pretty(map)}"
  end

  test "can detect missing :cmd", %{ctrl_maps: cm} do
    job = find_job(cm, :indoor_garden)

    assert :undefined == get_in(job, [:finish, :cmd])
  end

  test "can detect device not found", %{ctrl_maps: cm} do
    for map <- cm do
      assert is_map_key(map, :device)

      device = get_in(map, [:device])
      assert is_binary(device), "device #{inspect(device)} should be binary"
    end
  end

  @tag state_args: [cfg_file: cfg_toml_file(:invalid)]
  test "can detect invalid config (missing device)", %{ctrl_maps: cm} do
    job = find_job(cm, :no_device)

    fail = "should be :device == :missing#{pretty(job)}"
    assert get_in(job, [:device]) == :missing, fail

    fail = ":invalid should be a list#{pretty(job)}"
    invalid = get_in(job, [:invalid])
    assert is_list(invalid), fail

    fail = "length(:invalid) should be == 1#{pretty(job)}"
    assert length(invalid) == 1, fail

    fail = "invalid message should contain 'missing'#{pretty(job)}"
    assert hd(invalid) =~ "missing", fail
  end

  @tag state_args: [cfg_file: cfg_toml_file(:invalid)]
  test "can detect invalid config (bad :start cmd)", %{ctrl_maps: cm} do
    bad_cmd = find_job(cm, :bad_cmd)
    invalid = get_in(bad_cmd, [:start, :invalid])
    fail = ":invalid should exist in :start#{pretty(bad_cmd)}"
    assert is_list(invalid), fail
  end

  @tag state_args: [cfg_file: cfg_toml_file(:invalid)]
  test "can detect invalid config (:start missing cmd)", %{ctrl_maps: cm} do
    missing_cmd = find_job(cm, :missing_cmd)
    invalid = get_in(missing_cmd, [:invalid])
    fail = ":invalid should be a list#{pretty(invalid)}"
    assert is_list(invalid), fail

    fail = ":invalid should be length == 1"
    assert length(invalid) == 2, fail
  end

  @tag state_args: [cfg_file: cfg_toml_file(:invalid)]
  test "can is_valid?/1 detect an invalid control map", %{ctrl_maps: cm} do
    # import the macro
    import Lights.ControlMap, only: [is_valid?: 1]
    bad_cmd = find_job(cm, :bad_cmd)

    fail = "is_valid? should return false#{pretty(bad_cmd)}"
    refute is_valid?(bad_cmd), fail
  end
end
