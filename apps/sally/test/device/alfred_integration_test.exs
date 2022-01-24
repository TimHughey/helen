defmodule Sally.DevAliasAlfredIntegrationTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_alfred_integration: true

  # NOTE: devalias_add/1 automatically registers the name via Sally.DevAlias.just_saw/2
  # ** if this behaviour is NOT desired include register: false in devalias_add opts

  defmacro assert_dev_alias do
    quote do
      %{dev_alias: %Sally.DevAlias{name: name, ttl_ms: ttl_ms} = dev_alias} = var!(ctx)
      assert %{name: ^name, nature: :cmds, ttl_ms: ^ttl_ms} = Alfred.name_info(name)

      {dev_alias, name}
    end
  end

  setup [:dev_alias_add]

  describe "Alfred.status/2 integration with Sally.DevAlias" do
    @tag dev_alias_add: [auto: :mcp23008]
    test "returns well formed Alfred.status for new mutable DevAlias (no cmds)", ctx do
      {_dev_alias, name} = assert_dev_alias()

      # NOTE: cmd == "unknown" because this DevAlias did not have commands
      # Sally.DevAlias.Command.status/2 automatically adds an unknown command
      # when the DevAlias does not have any commands
      assert %Alfred.Status{rc: :ok, detail: %{cmd: "unknown"}} = Alfred.status(name, [])
    end

    @tag dev_alias_add: [auto: :pwm, cmds: [history: 1, latest: :pending, echo: :instruct]]
    test "returns well formed Alfred.status for new mutable DevAlias (with one cmd)", ctx do
      # NOTE: confirm the cmd was sent
      assert_receive(%Sally.Host.Instruct{}, 10)

      {_dev_alias, name} = assert_dev_alias()

      # NOTE: confirm attempt to exevute another cmd is prevented due to pending status
      assert %{cmd_latest: [%{rc: :pending, detail: %{cmd: cmd}}]} = ctx
      assert %Alfred.Status{rc: :pending, detail: %{cmd: ^cmd}} = Alfred.status(name, [])
    end
  end
end
