defmodule HelenDevicesTest do
  use ExUnit.Case, async: true

  import HelenTestHelpers, only: [pretty: 1]

  @moduletag :helen_devices

  def setup_ctx(ctx) do
    device = ctx[:device]

    initial_state = %{opts: %{tz: "America/New_York"}}

    if is_binary(device) do
      s = MutableDevices.locate(initial_state, device)

      cache = get_in(s, [:device_cache])
      fail = "state should have :device_cache#{pretty(s)}"
      assert is_map(cache), fail

      entry = get_in(s, [:device_cache, device])
      fail = "device cache entry should be a tuple#{pretty(s)}"
      assert is_tuple(entry) and tuple_size(entry) == 3, fail

      put_in(ctx, [:state], s) |> put_in([:entry], entry)
    else
      put_in(ctx, [:state], initial_state)
    end
  end

  setup ctx do
    {:ok, setup_ctx(ctx)}
  end

  @tag device: "irrigation 12v power"
  test "can locate a device", %{state: s, entry: entry} do
    fail = "device should be found#{pretty(s)}"
    {rc, mod, at} = entry
    assert :found == rc, fail
    assert Switch == mod, fail
    assert %DateTime{} = at, fail
  end

  @tag device: "unknown"
  test "can detect device not found while locating", %{
    state: s,
    device: device,
    entry: entry
  } do
    fail = "device #{device} should be not found#{pretty(s)}"
    {rc, _mod, _at} = entry

    assert :not_found == rc, fail
  end

  @tag device: "irrigation 12v power"
  test "can determine if a device exists", %{state: s, device: device} do
    fail = "exists?/2 should return true"
    assert MutableDevices.exists?(device, s), fail
  end

  @tag device: "irrigation 12v power"
  test "can force a device locate", %{state: s, device: device} do
    s = MutableDevices.locate(s, device, force: true)

    fail = "exists?/2 should return true"
    assert MutableDevices.exists?(device, s), fail
  end

  @tag device: "irrigation 12v power"
  test "can pass a list of mods to locate/3", %{state: s, device: device} do
    s =
      MutableDevices.locate(s, device,
        force: true,
        mods: [NotAModule, NeverAModule]
      )

    fail = "exists?/2 should return false"
    refute MutableDevices.exists?(device, s), fail
  end

  @tag device: "irrigation 12v power"
  test "can locate a device already in cache", %{state: s, device: device} do
    s =
      MutableDevices.locate(s, device)
      |> MutableDevices.locate("unknown", force: true)

    fail = "exists?/2 should return true"
    assert MutableDevices.exists?(device, s), fail
  end
end