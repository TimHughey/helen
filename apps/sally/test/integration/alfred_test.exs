defmodule Sally.DevAliasAlfredIntegrationTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  import ExUnit.CaptureLog

  @moduletag sally: true, sally_alfred_integration: true

  # NOTE: devalias_add/1 automatically registers the name via Sally.DevAlias.register/2
  # ** if this behaviour is NOT desired include register: false in devalias_add opts

  defmacro assert_dev_alias do
    quote do
      %{dev_alias: %Sally.DevAlias{name: name, ttl_ms: ttl_ms} = dev_alias} = var!(ctx)
      assert %{name: ^name, nature: :cmds, ttl_ms: ^ttl_ms} = Alfred.name_info(name)

      {dev_alias, name}
    end
  end

  setup [:dev_alias_add]

  describe "Sally.DevAlias integration with Alfred.status" do
    @tag dev_alias_add: [auto: :mcp23008]
    test "mutable (no cmds) rc: :ok", ctx do
      {_dev_alias, name} = assert_dev_alias()

      # NOTE: cmd == "unknown" because this DevAlias did not have commands
      # Sally.DevAlias.Command.status/2 automatically adds an unknown command
      # when the DevAlias does not have any commands

      {status, log} = with_log(fn -> Alfred.status(name, []) end)
      assert %Alfred.Status{rc: :ok, detail: %{cmd: "unknown"}} = status

      assert log =~ ~r(mfa=Sally.Command.status_log_unknown/2)
    end

    @tag dev_alias_add: [auto: :pwm, cmds: [history: 1, latest: :busy, echo: :instruct]]
    test "mutable (with one cmd) :busy", ctx do
      # NOTE: confirm the cmd was sent
      assert_receive(%Sally.Host.Instruct{}, 10)

      {_dev_alias, name} = assert_dev_alias()

      # NOTE: confirm attempt to exevute another cmd is prevented due to busy status
      assert %{cmd_latest: %{acked: false, acked_at: nil, cmd: cmd}} = ctx

      status = Alfred.status(name, [])
      assert %Alfred.Status{rc: :busy, detail: %{cmd: ^cmd}} = status
    end

    @tag capture_log: true
    @tag dev_alias_add: [auto: :pwm, cmds: [history: 1, latest: :orphan, echo: :instruct]]
    test "mutable (with cmd timeout", ctx do
      # NOTE: confirm the cmd was sent
      assert_receive(%Sally.Host.Instruct{}, 10)
      Process.sleep(10)

      {dev_alias, name} = assert_dev_alias()

      # NOTE: confirm attempt to exevute another cmd is prevented due to busy status
      assert %{acked: true, orphaned: true, cmd: cmd} = Sally.Command.saved(dev_alias)

      status = Alfred.status(name, [])

      assert %Alfred.Status{rc: rc, detail: %{cmd: ^cmd}} = status
      assert {:timeout, ms} = rc
      assert is_integer(ms) and ms > 1
    end

    @tag dev_alias_add: [auto: :ds, daps: [history: 90, seconds: -1]]
    test "immutable (with history)", ctx do
      assert %{dev_alias: %Sally.DevAlias{name: name}} = ctx

      assert %{rc: :ok, detail: detail} = Alfred.status(name, since_ms: 60_000)
      assert %{points: points} = detail

      history_avg = Sally.DatapointAid.avg_daps(ctx, points)

      Enum.each(history_avg, fn {k, v} -> assert_in_delta(v, Map.get(detail, k), 0.01) end)
    end

    @tag dev_alias_add: [auto: :ds]
    test "immutable (without history)", ctx do
      assert %{dev_alias: %Sally.DevAlias{name: name}} = ctx

      assert %{rc: :no_data, detail: %{}} = Alfred.status(name, since_ms: 60_000)
    end
  end

  describe "Alfred.execute/2 integration with Sally.DevAlias" do
    @tag dev_alias_add: [auto: :pwm, count: 3, cmds: [history: 15]]
    test "does not issue a cmd/instruction to the remote host when same cmd", ctx do
      assert %{dev_alias: [_ | _] = dev_aliases} = ctx

      dev_alias = Sally.DevAliasAid.random_pick(dev_aliases)
      assert %Sally.DevAlias{name: dev_alias_name} = dev_alias
      assert cmd_status = Sally.Command.status(dev_alias_name, [])
      assert %Sally.DevAlias{status: status} = cmd_status
      assert %{id: before_id} = status

      assert %Alfred.Status{rc: :ok, detail: detail} = Alfred.status(dev_alias_name, [])
      assert %{cmd: before_cmd, id: ^before_id} = detail

      cmd_opts = [name: dev_alias_name, cmd: before_cmd, echo: :instruct]
      execute = Alfred.execute(cmd_opts, [])

      assert %Alfred.Execute{rc: :ok, name: ^dev_alias_name, detail: detail} = execute
      assert %{acked: true, cmd: ^before_cmd, id: ^before_id} = detail
    end

    @tag dev_alias_add: [auto: :pwm, count: 3, cmds: [history: 15]]
    test "issues a cmd/instruction to the remote host when different cmd", ctx do
      assert %{dev_alias: [%Sally.DevAlias{} | _] = dev_aliases} = ctx

      dev_alias = Sally.DevAliasAid.random_pick(dev_aliases)
      assert %Sally.DevAlias{name: dev_alias_name} = dev_alias

      new_cmd = Sally.CommandAid.random_cmd()
      cmd_opts = [name: dev_alias_name, cmd: new_cmd, echo: :instruct]
      execute = Alfred.execute(cmd_opts, [])

      assert %Alfred.Execute{rc: :busy, name: ^dev_alias_name, detail: detail} = execute
      assert %{cmd: ^new_cmd} = detail

      status = Alfred.status(dev_alias_name, [])
      assert %Alfred.Status{rc: :busy, detail: %{cmd: ^new_cmd}} = status

      assert_receive(%Sally.Host.Instruct{}, 100)
    end
  end
end
