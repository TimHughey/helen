defmodule Rena.SetPt.CmdTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag rena: true, setpt_cmd_test: true

  alias Alfred.{ExecCmd, ExecResult}
  alias Alfred.MutableStatus, as: MutStatus
  alias Rena.Sensor.Result
  alias Rena.SetPt.Cmd

  defmacro check_exec_cmd(name, cmd, action, res) do
    quote location: :keep, bind_quoted: [name: name, cmd: cmd, action: action, res: res] do
      should_be_rc_tuple_with_struct(res, action, ExecCmd)

      {_, %ExecCmd{} = ec} = res
      should_be_equal(ec.name, name)
      should_be_equal(ec.cmd, cmd)
    end
  end

  describe "Rena.SetPt.Cmd.make/3 returns" do
    setup [:assemble_result]

    @tag result_opts: [lt_low: 3]
    test "active cmd when low value and inactive", %{result: r} do
      name = "mutable power off"

      res = Cmd.make(name, r, alfred: Rena.Alfred)

      check_exec_cmd(name, "on", :activate, res)
    end

    @tag result_opts: [gt_high: 1, gt_mid: 2]
    test "inactive cmd when high value and active", %{result: r} do
      name = "mutable power on"

      res = Cmd.make(name, r, alfred: Rena.Alfred)

      check_exec_cmd(name, "off", :deactivate, res)
    end

    @tag result_opts: [gt_mid: 2]
    test "datapoint error when only two datapoints", %{result: r} do
      name = "mutable power on"

      res = Cmd.make(name, r, alfred: Rena.Alfred)

      should_be_tuple_with_size(res, 2)
      {rc, struct} = res
      should_be_equal(rc, :datapoint_error)
      should_be_struct(struct, Result)
    end

    @tag result_opts: [lt_mid: 2, gt_mid: 1]
    test "no change when result below mid range value and active", %{result: r} do
      name = "mutable power on"

      res = Cmd.make(name, r, alfred: Rena.Alfred)

      should_be_equal(res, {:no_change, :active})
    end

    @tag result_opts: [lt_low: 3]
    test "equipment error tuple with MutableStatus not good", %{result: r} do
      name = "mutable bad on"

      res = Cmd.make(name, r, alfred: Rena.Alfred)

      should_be_tuple_with_size(res, 2)

      {rc, mut_status} = res
      should_be_equal(rc, :equipment_error)
      should_be_struct(mut_status, MutStatus)
    end
  end

  describe "Rena.SetPt.Cmd.effectuate/2" do
    setup [:setup_opts]

    test "handles datapoint errors", %{opts: opts} do
      res = Cmd.effectuate({:datapoint_error, :foo}, opts)
      should_be_equal(res, :failed)
    end

    test "handles general error", %{opts: opts} do
      res = Cmd.effectuate({:error, :foo}, opts)
      should_be_equal(res, :failed)
    end

    test "handles equipment ttl expired", %{opts: opts} do
      res = Cmd.effectuate({:equipment_error, %MutStatus{name: "bad equipment", ttl_expired?: true}}, opts)
      should_be_equal(res, :failed)
    end

    test "handles equipment error", %{opts: opts} do
      res = Cmd.effectuate({:equipment_error, %MutStatus{name: "bad equipment", error: :unknown}}, opts)
      should_be_equal(res, :failed)
    end

    test "handles no change", %{opts: opts} do
      res = Cmd.effectuate({:no_change, :foo}, opts)
      should_be_equal(res, :no_change)
    end
  end

  test "Rena.SetPt.Cmd.execute/2 executes an ExecCmd" do
    opts = [alfred: Rena.Alfred, server_name: __MODULE__]

    ec = %ExecCmd{name: "mutable good on", cmd: "on"}
    res = Cmd.execute(ec, opts)
    should_be_ok_tuple_with_struct(res, ExecResult)
    {_rc, exec_result} = res
    should_be_equal(exec_result.rc, :ok)

    ec = %ExecCmd{name: "mutable pending on", cmd: "on"}
    res = Cmd.execute(ec, opts)
    should_be_ok_tuple_with_struct(res, ExecResult)
    {_rc, exec_result} = res
    should_be_equal(exec_result.rc, :pending)

    ec = %ExecCmd{name: "mutable bad on", cmd: "on"}
    res = Cmd.execute(ec, opts)
    should_be_failed_tuple_with_struct(res, ExecResult)
    {_rc, exec_result} = res
    should_be_equal(exec_result.rc, {:ttl_expired, 10_000})
  end

  defp assemble_result(%{result_opts: opts} = ctx) do
    result =
      for {key, val} <- opts, reduce: %Result{} do
        r ->
          case key do
            x when x in [:lt_low, :lt_mid, :gt_mid, :gt_high] ->
              Map.update!(r, :valid, fn x -> x + val end) |> Map.put(key, val)

            :invalid ->
              Map.put(r, :invalid, val)

            _ ->
              r
          end
      end
      |> finalize_result_total()

    Map.put(ctx, :result, result)
  end

  defp assemble_result(ctx), do: ctx

  defp finalize_result_total(%Result{valid: valid, invalid: invalid} = r) do
    %Result{r | total: valid + invalid}
  end

  defp setup_opts(ctx) do
    Map.put(ctx, :opts, server_name: Rena.SetPt.ServerTest)
  end
end
