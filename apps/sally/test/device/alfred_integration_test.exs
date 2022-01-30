defmodule Sally.DevAliasAlfredIntegrationTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  import ExUnit.CaptureLog

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

      {status, log} = with_log(fn -> Alfred.status(name, []) end)
      assert %Alfred.Status{rc: :ok, detail: %{cmd: "unknown"}} = status

      assert log =~ ~r/cmd is unknown/
    end

    @tag dev_alias_add: [auto: :pwm, cmds: [history: 1, latest: :busy, echo: :instruct]]
    test "returns well formed Alfred.status for new mutable DevAlias (with one cmd)", ctx do
      # NOTE: confirm the cmd was sent
      assert_receive(%Sally.Host.Instruct{}, 10)

      {_dev_alias, name} = assert_dev_alias()

      # NOTE: confirm attempt to exevute another cmd is prevented due to busy status
      assert %{cmd_latest: %{acked: false, acked_at: nil, cmd: cmd}} = ctx

      status = Alfred.status(name, [])
      assert %Alfred.Status{rc: :busy, detail: %{cmd: ^cmd}} = status
    end
  end

  describe "Alfred.execute/2 integration with Sally.DevAlias" do
    @tag dev_alias_add: [auto: :pwm, count: 3, cmds: [history: 1]]
    test "does not issue a cmd/instruction to the remote host when same cmd", ctx do
      assert %{dev_alias: [%Sally.DevAlias{} | _] = dev_aliases} = ctx

      dev_alias = Sally.DevAliasAid.random_pick(dev_aliases)
      assert %Sally.DevAlias{name: dev_alias_name} = dev_alias
      assert cmd_status = Sally.Command.status(dev_alias, [])
      assert %Sally.DevAlias{cmds: [%Sally.Command{} = raw_cmd]} = cmd_status
      assert %{id: before_id} = raw_cmd

      assert %Alfred.Status{rc: :ok, detail: detail} = Alfred.status(dev_alias_name, [])
      assert %{cmd: before_cmd, id: ^before_id} = detail

      cmd_opts = [name: dev_alias_name, cmd: before_cmd, echo: :instruct]
      execute = Alfred.execute(cmd_opts, [])

      assert %Alfred.Execute{rc: :ok, name: ^dev_alias_name, detail: detail} = execute
      assert %{acked: true, cmd: ^before_cmd, id: ^before_id} = detail
    end
  end
end
