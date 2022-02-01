defmodule Alfred.TrackTest do
  use ExUnit.Case, async: true

  @moduletag alfred: true, alfred_track: true

  describe "Alfred.track.track/3" do
    test "starts server for refid" do
      refid = Alfred.Track.make_refid()

      assert {:ok, pid} = Alfred.Track.track(%{refid: refid}, __MODULE__, [])
      assert Process.alive?(pid)
    end
  end

  describe "Alfred.Track.release/3" do
    test "stops server for refid" do
      refid = Alfred.Track.make_refid()

      assert {:ok, pid} = Alfred.Track.track(%{refid: refid}, __MODULE__, [])
      assert Process.alive?(pid)

      assert :ok = Alfred.Track.release(refid, __MODULE__, [])
      refute Process.alive?(pid)
    end
  end

  describe "Alfred.Track.handle_info/2 (timeout)" do
    test "handles function not available" do
      refid = Alfred.Track.make_refid()

      cmd_opts = [timeout_ms: 1, notify_when_released: true]
      assert {:ok, pid} = Alfred.Track.track(%{refid: refid}, __MODULE__, cmd_opts: cmd_opts)
      assert is_pid(pid)
      assert Process.alive?(pid)

      assert_receive({Alfred, %Alfred.Track{rc: :timeout}}, 50)

      tag_values = Betty.measurement("app_error", :tag_values)

      assert Enum.any?(tag_values[:module], fn val -> val == __MODULE__ end)
      assert Enum.any?(tag_values[:refid], fn {_key, val} -> val == refid end)

      refute Process.alive?(pid)
    end
  end

  describe "Alfred.Track" do
    test "sends msg when refid released" do
      refid = Alfred.Track.make_refid()
      # NOTE: create a unique cmd and name for validation of Betty metric
      cmd = Alfred.Track.make_refid()
      name = Alfred.Track.make_refid()

      track_map = %{refid: refid}
      opts = [cmd: cmd, name: name, cmd_opts: [timeout_ms: 100, notify_when_released: true]]

      assert {:ok, pid} = Alfred.Track.track(track_map, __MODULE__, opts)
      assert is_pid(pid)
      assert Process.alive?(pid)

      assert :ok == Alfred.Track.release(refid, __MODULE__, [])

      assert_receive({Alfred, %Alfred.Track{rc: :ok}}, 50)

      Process.sleep(200)

      tag_values = Betty.measurement("runtime", :tag_values)

      assert Enum.any?(tag_values[:name], fn {_key, val} -> val == name end)
      assert Enum.any?(tag_values[:cmd], fn {_key, val} -> val == cmd end)

      refute Process.alive?(pid)
    end
  end
end
