defmodule Alfred.TrackTest do
  use ExUnit.Case, async: true
  use Alfred.TestAid

  @moduletag alfred: true, alfred_track: true

  use Alfred.Track

  # required callbacks
  @impl true
  def track_timeout(track), do: raise("#{inspect(track)}")

  setup [:equipment_add]

  describe "Alfred.track.track/3" do
    test "starts server for refid" do
      # NOTE: Alfred.Track requires the tracked item has the :track field
      refid = Alfred.Track.make_refid()
      item = %{refid: refid, track: nil}

      tracked_item = Alfred.Track.track(item, __MODULE__, [])

      assert %{refid: ^refid, track: tracked} = tracked_item
      assert {:ok, pid} = tracked
      assert Process.alive?(pid)
    end

    @tag equipment_add: [rc: :busy]
    test "sets tracked item to complete", ctx do
      assert %{dev_alias: dev_alias} = ctx
      assert %Alfred.DevAlias{cmds: [cmd]} = dev_alias
      assert %Alfred.Command{refid: refid, track: track} = cmd
      assert {:ok, pid} = track
      assert is_pid(pid) and Process.alive?(pid)

      now = Alfred.Command.now()

      assert :ok = Alfred.Command.track(:complete, refid, now)
      assert :ok = Alfred.Command.release(refid, [])

      assert_receive({Alfred, %Alfred.Track{}})
    end
  end

  describe "Alfred.Track.release/3" do
    test "stops server for refid" do
      # NOTE: Alfred.Track requires the tracked item has the :track field
      refid = Alfred.Track.make_refid()
      item = %{refid: refid, track: nil}

      tracked_item = Alfred.Track.track(item, __MODULE__, [])

      assert %{refid: ^refid, track: tracked} = tracked_item
      assert {:ok, pid} = tracked
      assert Process.alive?(pid)

      assert :ok = Alfred.Track.release(refid, __MODULE__, [])
      refute Process.alive?(pid)
    end
  end

  describe "Alfred.Track.handle_info/2 (timeout)" do
    @tag equipment_add: [rc: :busy, cmd_opts: [timeout_ms: 1, notify_when_released: true]]
    test "sends timeout message and records metrics", ctx do
      assert %{dev_alias: dev_alias} = ctx
      assert %Alfred.DevAlias{cmds: [cmd], name: name} = dev_alias
      assert %Alfred.Command{cmd: tracked_cmd, track: tracked} = cmd
      assert {:ok, pid} = tracked

      assert_receive({Alfred, %Alfred.Track{rc: :timeout}}, 50)

      Process.sleep(300)

      tag_values = Betty.measurement("app_error", :tag_values)

      assert Enum.any?(tag_values[:module], &match?(Alfred.Command, &1))
      assert Enum.any?(tag_values[:cmd], &match?({:cmd, ^tracked_cmd}, &1))
      assert Enum.any?(tag_values[:mutable], &match?({:mutable, ^name}, &1))

      refute Process.alive?(pid)
    end
  end

  describe "Alfred.Track" do
    @tag equipment_add: [rc: :busy, cmd_opts: [timeout_ms: 100, notify_when_released: true]]
    test "sends msg when refid released", ctx do
      assert %{dev_alias: dev_alias} = ctx
      assert %Alfred.DevAlias{cmds: [cmd], name: name} = dev_alias
      assert %Alfred.Command{cmd: tracked_cmd, refid: refid, track: tracked} = cmd
      assert {:ok, pid} = tracked

      assert :ok == Alfred.Command.release(refid, name: name)

      assert_receive({Alfred, %Alfred.Track{rc: :ok}}, 50)

      Process.sleep(300)

      tag_values = Betty.measurement("runtime", :tag_values)

      assert Enum.any?(tag_values[:name], &match?({:name, ^name}, &1))
      assert Enum.any?(tag_values[:cmd], &match?({:cmd, ^tracked_cmd}, &1))

      refute Process.alive?(pid)
    end
  end

  describe "Alfred.Track.tracked_info/1" do
    @tag equipment_add: [rc: :busy]
    test "returns tracked info for a refid or pid", ctx do
      assert %{dev_alias: dev_alias} = ctx
      assert %Alfred.DevAlias{cmds: [cmd]} = dev_alias
      assert %Alfred.Command{cmd: tracked_cmd, refid: refid, track: tracked} = cmd
      assert {:ok, pid} = tracked

      info = Alfred.Command.tracked_info(refid)

      assert %Alfred.Command{cmd: ^tracked_cmd, refid: ^refid} = info

      info = Alfred.Track.tracked_info(pid)

      assert %Alfred.Command{cmd: ^tracked_cmd, refid: ^refid} = info
    end
  end
end
