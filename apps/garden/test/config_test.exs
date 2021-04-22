defmodule LightsConfigTest do
  @moduledoc false

  use ExUnit.Case, async: true

  import GardenTestHelpers, only: [cfg_toml_file: 1, make_state: 1, pretty: 1]

  @moduletag :config

  def setup_ctx(args) do
    {rc, s} = make_state(args)

    assert :ok == rc, "state creation failed#{pretty(s)}"

    %{cfg: s.cfg, state: s}
  end

  setup ctx do
    args = get_in(ctx, [:state_args]) || :default

    {:ok, setup_ctx(args)}
  end

  @tag state_args: [cfg_file: cfg_toml_file(:not_found), confirm_state: false]
  test "can handle non-existant config file", %{state: s} do
    invalid = get_in(s, [:invalid])
    fail = "state should contain the list :invalid#{pretty(s)}"
    assert is_list(invalid), fail
    refute [] == invalid, fail

    msg = hd(invalid)
    fail = "invalid list should contain not found#{pretty(invalid)}"
    assert msg =~ "not found", fail
  end

  test "can load config", %{cfg: cfg, state: s} do
    assert is_map(cfg)
    assert is_map_key(s, :cfg)

    fstat = get_in(cfg, [:fstat])
    fail = "state cfg should contain :fstat#{pretty(s)}"
    refute is_nil(fstat), fail
    assert %File.Stat{} = fstat, fail

    %File.Stat{ctime: ctime, mtime: mtime, size: size} = fstat

    msg = fn x -> "cfg file #{x} should be > 0" end

    assert ctime > 0, msg.("ctime")
    assert mtime > 0, msg.("mtime")
    assert size > 0, msg.("size")
  end

  @tag state_args: [cfg_file: cfg_toml_file(:parse_fail), confirm_state: false]
  test "can detect config parse failure", %{state: s} do
    invalid = get_in(s, [:invalid])
    fail = "state should contain :invalid list#{pretty(s)}"
    assert is_list(invalid), fail
    refute [] == invalid, fail

    msg = hd(invalid)
    fail = "invalid list should contain parse fail#{pretty(invalid)}"
    assert msg =~ "parse fail", fail
  end

  test "can detect config file change and reload", %{state: %{args: args} = s} do
    cfg_file = "lighting.toml"

    tmp_dir = System.tmp_dir()
    refute is_nil(tmp_dir) == :ok, "unable to determine a suitable tmp directory"

    new_cfg_file = Path.join(tmp_dir, cfg_file)

    cfg_file_path = cfg_toml_file(:lighting)
    rc = File.cp(cfg_file_path, new_cfg_file)
    assert :ok == rc, "unable to cp #{inspect(cfg_file_path)} to #{inspect(new_cfg_file)}"

    {rc, new_fstat} = File.stat(new_cfg_file, time: :posix)
    assert :ok == rc, "unable to stat #{inspect(new_cfg_file)}"

    args = update_in(args, [:cfg_file], fn _x -> new_cfg_file end)
    s = put_in(s, [:args], args)

    s = Lights.Config.reload_if_needed(s)

    cfg_fstat = s.cfg.fstat

    refute is_nil(cfg_fstat)

    assert Map.equal?(cfg_fstat, new_fstat)
  end
end
