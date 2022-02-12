defmodule Rena.SetPt.CmdTest do
  use ExUnit.Case, async: true

  @moduletag rena: true, rena_setpt_cmd: true

  import Alfred.NamesAid, only: [equipment_add: 1]

  defmacro assert_exec_cmd(ctx, :datapoint_error) do
    quote bind_quoted: [ctx: ctx] do
      %{equipment: equipment, result: result} = ctx

      cmd_result = Rena.SetPt.Cmd.make(equipment, result, alfred: AlfredSim)
      assert {:datapoint_error, %Rena.Sensor.Result{}} = cmd_result
    end
  end

  defmacro assert_exec_cmd(ctx, action) do
    quote bind_quoted: [ctx: ctx, action: action] do
      %{equipment: equipment, result: result} = ctx

      expect_cmd = if(action == :activate, do: "on", else: "off")

      make_result = Rena.SetPt.Cmd.make(equipment, result, alfred: AlfredSim)

      # assert {^action, [{:cmd, ^expect_cmd}, {:name, ^equipment} | _]} = cmd_result
      #   assert {^action, %{cmd: ^expect_cmd, name: equipment}} = cmd_result
      assert %{action: ^action, next_cmd: ^expect_cmd, equipment: ^equipment} = make_result
    end
  end

  describe "Rena.SetPt.Cmd.make/3 returns" do
    setup [:equipment_add, :assemble_result]

    @tag equipment_add: [cmd: "off"]
    @tag result_opts: [lt_low: 3]
    test "active cmd when low value and inactive", ctx do
      assert_exec_cmd(ctx, :activate)
    end

    @tag equipment_add: [cmd: "on"]
    @tag result_opts: [gt_high: 1, gt_mid: 2]
    test "inactive cmd when high value and active", ctx do
      assert_exec_cmd(ctx, :deactivate)
    end

    @tag equipment_add: [cmd: "on"]
    @tag result_opts: [gt_mid: 2]
    test "datapoint error when only two datapoints", ctx do
      assert_exec_cmd(ctx, :datapoint_error)
    end

    @tag equipment_add: [cmd: "on"]
    @tag result_opts: [lt_mid: 2, gt_mid: 1]
    test "no change when result below mid range value and active", ctx do
      make_result = Rena.SetPt.Cmd.make(ctx.equipment, ctx.result, alfred: AlfredSim)
      assert %{action: :no_change} = make_result
    end

    @tag equipment_add: [rc: :timeout, cmd: "unknown"]
    @tag result_opts: [lt_low: 3]
    test "equipment error tuple with Alfred.Status not good", ctx do
      assert {:equipment_error, %Alfred.Status{}} =
               Rena.SetPt.Cmd.make(ctx.equipment, ctx.result, alfred: AlfredSim)
    end
  end

  describe "Rena.SetPt.Cmd.effectuate/2" do
    setup [:setup_opts]

    test "handles datapoint errors", %{opts: opts} do
      assert :failed = Rena.SetPt.Cmd.effectuate({:datapoint_error, :foo}, opts)
    end

    # test "handles general error", %{opts: opts} do
    #   assert :failed = Rena.SetPt.Cmd.effectuate({:error, :foo}, opts)
    # end

    test "handles equipment ttl expired", %{opts: opts} do
      assert :failed =
               Rena.SetPt.Cmd.effectuate(
                 {:equipment_error, %Alfred.Status{name: "foo", rc: {:ttl_expired, 15_00}}},
                 opts
               )
    end

    test "handles equipment error", %{opts: opts} do
      assert :failed =
               Rena.SetPt.Cmd.effectuate(
                 {:equipment_error, %Alfred.Status{name: "foo", rc: :error}},
                 opts
               )
    end

    test "handles no change", %{opts: opts} do
      make_result = %{action: :no_change}
      assert :no_change = Rena.SetPt.Cmd.effectuate(make_result, opts)
    end
  end

  describe "Rena.SetPt.Cmd.execute/2" do
    setup [:setup_opts, :equipment_add]

    @tag equipment_add: [cmd: "on"]
    test "handles equipment status :ok", ctx do
      cmd_args = %{equipment: ctx.equipment, next_cmd: "on"}

      execute = Rena.SetPt.Cmd.execute(cmd_args, ctx.opts)
      assert %Alfred.Execute{rc: :ok, story: %{cmd: "on"}} = execute
    end

    @tag equipment_add: [busy: true, cmd: "on"]
    test "handles equipment status is :busy", ctx do
      cmd_args = %{equipment: ctx.equipment, next_cmd: "on"}

      execute = Rena.SetPt.Cmd.execute(cmd_args, ctx.opts)
      assert %Alfred.Execute{rc: :busy} = execute
    end

    @tag equipment_add: [busy: true, cmd: "on"]
    test "handles equipment status is :busy and next cmd is diff", ctx do
      cmd_args = %{equipment: ctx.equipment, next_cmd: "off"}

      execute = Rena.SetPt.Cmd.execute(cmd_args, ctx.opts)
      assert %Alfred.Execute{rc: :busy} = execute
    end

    @tag equipment_add: [expired_ms: 10_000]
    test "handles when equipment status is :ttl_expired", ctx do
      cmd_args = %{equipment: ctx.equipment, next_cmd: "on"}

      execute = Rena.SetPt.Cmd.execute(cmd_args, ctx.opts)
      assert %Alfred.Execute{rc: {:ttl_expired, ms}} = execute

      assert_in_delta(ms, 10_000, 1000)
    end
  end

  defp assemble_result(%{result_opts: opts}) do
    result =
      for {key, val} <- opts, reduce: %Rena.Sensor.Result{} do
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

  defp finalize_result_total(%Rena.Sensor.Result{valid: valid, invalid: invalid} = r) do
    %Rena.Sensor.Result{r | total: valid + invalid}
  end

  defp setup_opts(ctx) do
    opts = ctx[:setup_opts] || []
    %{opts: [alfred: AlfredSim, server_name: Rena.SetPt.ServerTest] ++ opts}
  end
end
