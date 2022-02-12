defmodule UseCarol.Alpha do
  use Carol, otp_app: :carol
end

defmodule UseCarol.Beta do
  use Carol, otp_app: :carol
end

defmodule CarolTest do
  use ExUnit.Case

  @moduletag carol: true, carol_use: true

  setup [:opts_add, :start_args_add, :start_supervised_add]

  describe "UseCarol.Alpha" do
    @tag skip: false
    test "config/0 returns list" do
      assert [instances: [_ | _], opts: [alfred: AlfredSim], otp_app: :carol] = UseCarol.Alpha.config()
    end

    test "instances/0 returns list" do
      assert [:first, :last, :second] = UseCarol.Alpha.instances()
    end

    test "can be started as a Supervisor" do
      child_spec = UseCarol.Alpha.child_spec([])

      assert {:ok, _pid} = start_supervised(child_spec)

      children = Supervisor.which_children(UseCarol.Alpha)

      Enum.all?(children, fn {mod, _pid, :worker, _mods} ->
        assert [_ | _] = Carol.state(mod, :all)
      end)
    end
  end

  describe "UseCarol.Beta" do
    test "can get status for an instance via fuzzy match" do
      import ExUnit.CaptureIO, only: [capture_io: 1]
      child_spec = UseCarol.Beta.child_spec([])

      assert {:ok, _pid} = start_supervised(child_spec)

      capture_io(fn ->
        assert :ok == UseCarol.Beta.status("first")
      end)

      assert :pause = UseCarol.Beta.pause("first")
      assert :ok = UseCarol.Beta.resume(:first)
    end
  end

  describe "Carol misc" do
    @tag start_args_add: {:app, :carol, CarolWithEpisodes, :first_instance}
    @tag start_supervised_add: []
    test "status/2 returns list of binary status", ctx do
      assert [<<_::binary>>, <<_::binary>> | _] = Carol.status(ctx.server_name)
    end
  end

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  defp opts_add(ctx), do: Carol.OptsAid.add(ctx)

  defp start_args_add(ctx), do: Carol.StartArgsAid.add(ctx)

  defp start_supervised_add(%{start_supervised_add: _, child_spec: child_spec}) do
    assert {:ok, pid} = start_supervised(child_spec)

    %{server_pid: pid}
  end

  defp start_supervised_add(_x), do: :ok
end
