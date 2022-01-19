defmodule Sally.DevAliasAlfredIntegrationTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_alfred_integration: true

  setup_all do
    # always create and setup a host
    {:ok, %{host_add: [], host_setup: []}}
  end

  # NOTE: devalias_add/1 automatically registers the name via Sally.DevAlias.just_saw/2
  # ** if this behaviour is NOT desired include register: false in devalias_add opts
  setup [:host_add, :host_setup, :device_add, :devalias_add, :command_add, :datapoint_add]

  defmacro assert_dev_alias do
    quote do
      %{dev_alias: %Sally.DevAlias{name: name, ttl_ms: ttl_ms} = dev_alias} = var!(ctx)
      assert %{name: ^name, nature: :cmds, ttl_ms: ^ttl_ms} = Alfred.name_info(name)

      {dev_alias, name}
    end
  end

  describe "Alfred.status/2 integration with Sally.DevAlias" do
    @tag device_add: [auto: :mcp23008], devalias_add: []
    test "returns well formed Alfred.status for new mutable DevAlias (no cmds)", ctx do
      {_dev_alias, name} = assert_dev_alias()

      # NOTE: cmd == "unknown" because this DevAlias did not have any commands
      # Sally.DevAlias.Command.status/2 automatically adds an unknown command when the DevAlias does
      # not have any commands
      assert %Alfred.Status{rc: :ok, detail: %{cmd: "unknown"}} = Alfred.status(name, [])
    end

    @tag device_add: [auto: :mcp23008],
         devalias_add: [],
         command_add: [cmd: "on", cmd_opts: [ack: :immediate]]
    test "returns well formed Alfred.status for new mutable DevAlias (cmd == on)", ctx do
      {_dev_alias, name} = assert_dev_alias()

      assert %Alfred.Status{rc: :ok, detail: %{cmd: "on"}} = Alfred.status(name, [])
    end
  end
end
