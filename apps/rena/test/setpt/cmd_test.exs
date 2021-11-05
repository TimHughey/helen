defmodule Rena.SetPt.CmdTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag rena: true, setpt_cmd_test: true

  alias Alfred.ExecCmd
  alias Alfred.MutableStatus, as: MutStatus
  alias Rena.Sensor.Result
  alias Rena.SetPt.Cmd

  defmacro check_exec_cmd(name, cmd, res) do
    quote location: :keep, bind_quoted: [name: name, cmd: cmd, res: res] do
      should_be_ok_tuple_with_struct(res, ExecCmd)

      {:ok, %ExecCmd{} = ec} = res
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

      check_exec_cmd(name, "on", res)
    end

    @tag result_opts: [gt_high: 1, gt_mid: 2]
    test "inactive cmd when high value and active", %{result: r} do
      name = "mutable power on"

      res = Cmd.make(name, r, alfred: Rena.Alfred)

      check_exec_cmd(name, "off", res)
    end

    @tag result_opts: [gt_mid: 2, lt_mid: 1]
    test "inactive cmd when above mid range value and active", %{result: r} do
      name = "mutable power on"

      res = Cmd.make(name, r, alfred: Rena.Alfred)

      check_exec_cmd(name, "off", res)
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
    test "equipment error tuple with MutableStatus is not good", %{result: r} do
      name = "mutable bad on"

      res = Cmd.make(name, r, alfred: Rena.Alfred)

      should_be_tuple_with_size(res, 2)

      {rc, mut_status} = res
      should_be_equal(rc, :equipment_error)
      should_be_struct(mut_status, MutStatus)
    end
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
end
