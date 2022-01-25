defmodule SallyDevAliasExplainTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_dev_alias_explain: true

  setup [:dev_alias_add]

  describe "Sally.DevAlias EXPLAIN" do
    @tag dev_alias_add: [auto: :mcp23008, cmds: [history: 100]]
    test "for join of last Sally.Command", ctx do
      assert %{dev_alias: %Sally.DevAlias{name: name}} = ctx

      explain_output = Sally.DevAlias.explain(name, :status, :cmds, [])

      assert explain_output =~ ~r/Index Scan/
      assert explain_output =~ ~r/Sort Method: top-N heapsort/
    end

    @tag dev_alias_add: [auto: :mcp23008, cmds: [history: 100]]
    test "for latest Sally.Command", ctx do
      assert %{dev_alias: %Sally.DevAlias{name: name}} = ctx

      explain_output = Sally.DevAlias.explain(name, :cmdack, :cmds, [])
      assert explain_output =~ ~r/Sort Method: top-N heapsort/
      assert explain_output =~ ~r/Index Scan/
      assert explain_output =~ ~r/Index Cond/
    end

    @tag dev_alias_add: [auto: :ds, daps: [history: 100]]
    test "for join of recent Sally.Datapoint", ctx do
      assert %{dev_alias: %Sally.DevAlias{name: name}} = ctx

      explain_output = Sally.DevAlias.explain(name, :status, :datapoints, [])
      assert explain_output =~ ~r/Join Filter/
      assert explain_output =~ ~r/Index Scan/
      assert explain_output =~ ~r/Sort Method: quicksort/
    end
  end
end
