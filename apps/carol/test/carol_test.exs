defmodule UseCarol.Alpha do
  use Carol, otp_app: :carol
end

defmodule UseCarol.Beta do
  use Carol, otp_app: :carol
end

defmodule CarolTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag carol: true, carol_use: true

  setup [:opts_add, :start_args_add, :start_supervised_add]

  describe "UseCarol.Alpha" do
    @tag skip: true
    test "config/0 returns list" do
      want_kv = [otp_app: :use_carol, instances: [first: [], second: [], last: []]]

      UseCarol.Alpha.config()
      |> Should.Be.NonEmpty.list()
      |> Should.Contain.kv_pairs(want_kv)
    end

    test "instances/0 returns list" do
      instance_list = [:first, :last, :second]

      UseCarol.Alpha.instances()
      |> Should.Be.equal(instance_list)
    end

    test "can be started as a Supervisor" do
      child_spec = UseCarol.Alpha.child_spec([])

      start_supervised(child_spec)
      |> Should.Be.Ok.tuple_with_pid()

      for {mod, _pid, :worker, _mods} <- Supervisor.which_children(UseCarol.Alpha) do
        Carol.state(mod, :all) |> Should.Contain.kv_pairs(cmd_live: :none)
      end
    end
  end

  describe "UseCarol.Beta" do
    test "can get status for an instance via fuzzy match" do
      import ExUnit.CaptureIO, only: [capture_io: 1]
      child_spec = UseCarol.Beta.child_spec([])

      start_supervised(child_spec)
      |> Should.Be.Ok.tuple_with_pid()

      capture_io(fn ->
        UseCarol.Beta.status("first") |> Should.Be.ok()
      end)

      UseCarol.Beta.pause("first") |> Should.Be.equal(:pause)
      UseCarol.Beta.resume(:first) |> Should.Be.equal(:ok)
    end
  end

  describe "Carol misc" do
    @tag start_args_add: {:app, :carol, CarolWithEpisodes, :first_instance}
    @tag start_supervised_add: []
    test "status/2 returns list of binary status", ctx do
      Carol.status(ctx.server_name)
      |> Should.Be.List.of_binaries()
    end
  end

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  defp opts_add(ctx), do: Carol.OptsAid.add(ctx)

  defp start_args_add(ctx), do: Carol.StartArgsAid.add(ctx)

  defp start_supervised_add(%{start_supervised_add: _} = ctx) do
    case ctx do
      %{child_spec: child_spec} -> start_supervised(child_spec) |> Should.Be.Ok.tuple_with_pid()
      _ -> :no_child_spec
    end
    |> then(fn pid -> %{server_pid: pid} end)
  end

  defp start_supervised_add(_x), do: :ok
end
