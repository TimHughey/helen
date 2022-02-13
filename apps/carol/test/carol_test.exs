defmodule Carol.Alpha do
  use Carol, otp_app: :carol
end

defmodule Carol.Alpha.Test do
  use ExUnit.Case

  @moduletag carol: true, carol_use: true

  describe "Carol.Alpha" do
    @tag skip: false
    test "config/0 returns list" do
      assert [instances: [_ | _], opts: [alfred: AlfredSim], otp_app: :carol] = Carol.Alpha.config()
    end

    test "instances/0 returns list" do
      assert [:first, :last, :second] = Carol.Alpha.instances()
    end

    test "can be started as a Supervisor" do
      child_spec = Carol.Alpha.child_spec([])

      assert {:ok, _pid} = start_supervised(child_spec)

      children = Supervisor.which_children(Carol.Alpha)

      Enum.all?(children, fn {mod, _pid, :worker, _mods} ->
        pid = GenServer.whereis(mod)
        assert is_pid(pid)
        assert Process.alive?(pid)
      end)
    end
  end
end
