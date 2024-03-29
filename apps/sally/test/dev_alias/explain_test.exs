defmodule SallyDevAliasExplainTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_dev_alias_explain: true

  setup [:dev_alias_add]

  describe "Sally EXPLAIN" do
    @tag dev_alias_add: [auto: :mcp23008, cmds: [history: 50]]
    test "Sally.Command.status_query/1", ctx do
      assert %{dev_alias: %Sally.DevAlias{name: name}} = ctx

      explain_output = Sally.explain(name, :status, :cmds, [])

      assert explain_output =~ ~r/command_dev_alias_id_index/
      assert explain_output =~ ~r/Index Scan/
      assert explain_output =~ ~r/Sort Method/
    end

    @tag dev_alias_add: [auto: :ds, daps: [history: 50]]
    test "Sally.Datapoint.status_query/2", ctx do
      assert %{dev_alias: %Sally.DevAlias{name: name}} = ctx

      explain_output = Sally.explain(name, :status, :datapoints, [])
      %{execution: exec_ms, planning: plan_ms} = explain_times(explain_output)

      assert exec_ms < 1.0
      assert plan_ms < 2.0

      assert explain_output =~ ~r/Index Scan/
      assert explain_output =~ ~r/Sort Method/
    end

    @tag dev_alias_add: [auto: :mcp23008, count: 1, cmds: [history: 50]]
    test "Sally.Command.status_query/2 (with device and host)", ctx do
      assert %{dev_alias: %{name: name}} = ctx

      explain_output = Sally.explain(name, :status, :cmds, preload: :device_and_host)

      assert explain_output =~ ~r/command_dev_alias_id_index/
      assert explain_output =~ ~r/device_pkey/
      assert explain_output =~ ~r/host_pkey/

      assert explain_output =~ ~r/Sort Method/
      assert explain_output =~ ~r/Index Scan/
      assert explain_output =~ ~r/Index Cond/
    end

    @tag dev_alias_add: [auto: :mcp23008, count: 3, cmds: [history: 20]]
    test "Sally.Command.latest_cmd/2", ctx do
      assert %{dev_alias: [%Sally.DevAlias{} | _] = dev_aliases} = ctx

      %{name: name} = Sally.DevAliasAid.random_pick(dev_aliases)

      explain_output = Sally.explain(name, :latest, :cmds, [])

      assert explain_output =~ ~r/Sort Method/
      assert explain_output =~ ~r/Index Scan/
      assert explain_output =~ ~r/Index Cond/
    end

    @tag dev_alias_add: [auto: :pwm, count: 4, cmds: [history: 2]]
    test "Sally.DevAlias.load_aliases/2", ctx do
      assert %{dev_alias: [%Sally.DevAlias{} | _] = dev_aliases} = ctx

      %{name: name} = Sally.DevAliasAid.random_pick(dev_aliases)

      explain_output = Sally.explain(name, :dev_alias, :load_aliases, [])

      assert explain_output =~ ~r/Sort Method/
      assert explain_output =~ ~r/Index Scan/
      assert explain_output =~ ~r/Index Cond/
    end
  end

  @regex ~r/Planning Time: (?<planning>[0-9.]+).*Execution Time: (?<execution>[0-9.]+)/ms
  def explain_times(output) do
    output = IO.iodata_to_binary(output)

    Regex.named_captures(@regex, output)
    |> Enum.into(%{}, fn {key, val} -> {String.to_atom(key), Float.parse(val) |> elem(0)} end)
  end
end
