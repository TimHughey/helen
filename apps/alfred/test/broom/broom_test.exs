defmodule Alfred.BroomTest do
  use ExUnit.Case, async: true

  @moduletag alfred: true, alfred_broom: true

  describe "Alfred.Broom.track/3" do
    test "starts server for refid" do
      refid = Alfred.Broom.make_refid()

      assert {:ok, pid} = Alfred.Broom.track(%{refid: refid}, __MODULE__, [])
      assert Process.alive?(pid)
    end
  end

  describe "Alfred.Broom.release/3" do
    test "stops server for refid" do
      refid = Alfred.Broom.make_refid()

      assert {:ok, pid} = Alfred.Broom.track(%{refid: refid}, __MODULE__, [])
      assert Process.alive?(pid)

      assert :ok = Alfred.Broom.release(refid, __MODULE__, [])
      refute Process.alive?(pid)
    end
  end

  describe "Alfred.Server.handle_info/2 (timeout)" do
    test "handles function not available" do
      refid = Alfred.Broom.make_refid()

      cmd_opts = [timeout_ms: 1]
      assert {:ok, pid} = Alfred.Broom.track(%{refid: refid}, __MODULE__, cmd_opts: cmd_opts)
      assert is_pid(pid)
      assert Process.alive?(pid)

      Process.sleep(10)

      refute Process.alive?(pid)
    end
  end

  describe "Alfred.Server" do
    test "sends msg when refid released" do
      refid = Alfred.Broom.make_refid()

      cmd_opts = [timeout_ms: 100, notify_when_released: true]
      assert {:ok, pid} = Alfred.Broom.track(%{refid: refid}, __MODULE__, cmd_opts: cmd_opts)
      assert is_pid(pid)
      assert Process.alive?(pid)

      assert :ok == Alfred.Broom.release(refid, __MODULE__, [])

      assert_receive({Alfred, %Alfred.Broom{}}, 100)

      refute Process.alive?(pid)
    end
  end
end
