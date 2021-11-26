defmodule Rena.SetPt.CmdTest do
  use ExUnit.Case, async: true
  use Should
  use Alfred.NamesAid

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
    setup [:equipment_add, :assemble_result]

    @tag equipment_add: [cmd: "off"]
    @tag result_opts: [lt_low: 3]
    test "active cmd when low value and inactive", ctx do
      res = Cmd.make(ctx.equipment, ctx.result, alfred: Rena.Alfred)

      check_exec_cmd(ctx.equipment, "on", :activate, res)
    end

    @tag equipment_add: [cmd: "on"]
    @tag result_opts: [gt_high: 1, gt_mid: 2]
    test "inactive cmd when high value and active", ctx do
      res = Cmd.make(ctx.equipment, ctx.result, alfred: Rena.Alfred)

      check_exec_cmd(ctx.equipment, "off", :deactivate, res)
    end

    @tag equipment_add: [cmd: "on"]
    @tag result_opts: [gt_mid: 2]
    test "datapoint error when only two datapoints", ctx do
      res = Cmd.make(ctx.equipment, ctx.result, alfred: Rena.Alfred)

      should_be_tuple_with_size(res, 2)
      {rc, struct} = res
      should_be_equal(rc, :datapoint_error)
      should_be_struct(struct, Result)
    end

    @tag equipment_add: [cmd: "on"]
    @tag result_opts: [lt_mid: 2, gt_mid: 1]
    test "no change when result below mid range value and active", ctx do
      res = Cmd.make(ctx.equipment, ctx.result, alfred: Rena.Alfred)

      should_be_equal(res, {:no_change, :active})
    end

    @tag equipment_add: [rc: :error, cmd: "unknown"]
    @tag result_opts: [lt_low: 3]
    test "equipment error tuple with MutableStatus not good", ctx do
      res = Cmd.make(ctx.equipment, ctx.result, alfred: Rena.Alfred)

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

  describe "Rena.SetPt.Cmd.execute/2" do
    setup [:setup_opts, :equipment_add]

    @tag equipment_add: [cmd: "on"]
    test "handles equipment status :ok", ctx do
      ec = %ExecCmd{name: ctx.equipment, cmd: "on"}
      res = Cmd.execute(ec, ctx.opts)

      should_be_ok_tuple_with_struct(res, ExecResult)
      {_rc, exec_result} = res
      should_be_equal(exec_result.rc, :ok)
    end

    @tag equipment_add: [pending: true, cmd: "on"]
    test "handles equipment status is :pending", ctx do
      ec = %ExecCmd{name: ctx.equipment, cmd: "on"}
      res = Cmd.execute(ec, ctx.opts)

      should_be_ok_tuple_with_struct(res, ExecResult)
      {_rc, exec_result} = res
      should_be_equal(exec_result.rc, :pending)
    end

    @tag equipment_add: [expired_ms: 10_000]
    test "handles when equipment status is :ttl_expired", ctx do
      ec = %ExecCmd{name: ctx.equipment, cmd: "on"}
      res = Cmd.execute(ec, ctx.opts)

      should_be_failed_tuple_with_struct(res, ExecResult)
      {_rc, exec_result} = res
      should_be_equal(exec_result.rc, {:ttl_expired, 10_000})
    end
  end

  defp assemble_result(%{result_opts: opts}) do
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

    %{result: result}
  end

  defp assemble_result(_), do: :ok

  def equipment_add(%{equipment_add: opts}) do
    rc = opts[:rc] || :ok
    %{make_name: [type: :mut, rc: rc, key: :equipment] ++ opts} |> NamesAid.make_name()
  end

  def equipment_add(_) do
    %{make_name: [type: :mut, rc: :ok, cmd: "on", key: :equipment]}
    |> NamesAid.make_name()
  end

  defp finalize_result_total(%Result{valid: valid, invalid: invalid} = r) do
    %Result{r | total: valid + invalid}
  end

  defp setup_opts(ctx) do
    opts = ctx[:setup_opts] || []
    %{opts: [alfred: Rena.Alfred, server_name: Rena.SetPt.ServerTest] ++ opts}
  end
end
