defmodule SallyDevAliasExplainTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_dev_alias_explain: true

  setup [:dev_alias_add]

  describe "Sally EXPLAIN" do
    @tag dev_alias_add: [auto: :mcp23008, cmds: [history: 100]]
    test "Sally.Command.status_query/1", ctx do
      assert %{dev_alias: %Sally.DevAlias{name: name}} = ctx

      explain_output = Sally.explain(name, :status, :cmds, [])

      assert explain_output =~ ~r/Index Scan/
      assert explain_output =~ ~r/Sort Method/
    end

    @tag dev_alias_add: [auto: :ds, daps: [history: 100]]
    test "Sally.Datapoint.status_query/2", ctx do
      assert %{dev_alias: %Sally.DevAlias{name: name}} = ctx

      explain_output = Sally.explain(name, :status, :datapoints, [])

      assert explain_output =~ ~r/Join Filter/
      assert explain_output =~ ~r/Index Scan/
      assert explain_output =~ ~r/Sort Method/
    end

    @tag dev_alias_add: [auto: :mcp23008, count: 3, cmds: [history: 100]]
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
end
