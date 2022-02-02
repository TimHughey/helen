defmodule SallyCommandTest do
  use ExUnit.Case, async: true
  use Sally.TestAid
  use Timex

  @moduletag sally: true, sally_command: true

  setup [:dev_alias_add]

  describe "Sally.Command.track_timeout/1" do
    @tag capture_log: true
    @tag dev_alias_add: [auto: :mcp23008, cmds: [history: 2, latest: :busy]]
    test "acks a command as an orphan", ctx do
      assert %{dev_alias: dev_alias, cmd_latest: cmd} = ctx

      assert %Sally.DevAlias{id: dev_alias_id, name: name} = dev_alias
      assert %Sally.Command{acked: false, refid: refid} = cmd

      assert {:tracked, _pid} = Sally.Command.track(cmd, [])

      tracked_info = Sally.Command.tracked_info(refid)
      assert %Sally.Command{} = tracked_info

      track = %Alfred.Track{tracked_info: tracked_info}

      assert %Sally.Command{cmd: acked_cmd} = cmd = Sally.Command.track_timeout(track)

      assert %{acked: true, orphaned: true} = cmd
      assert %{acked_at: %DateTime{}, rt_latency_us: rt_us} = cmd
      assert %{dev_alias_id: ^dev_alias_id} = cmd

      assert is_integer(rt_us) and rt_us > 100

      assert %{rc: :orphan, detail: %{cmd: ^acked_cmd}} = Alfred.status(name)
    end
  end

  describe "Sally.Command.save/1" do
    @tag dev_alias_add: [auto: :pwm, cmds: [history: 2, latest: :busy]]
    test "replaces the command for a Sally.DevAlias", ctx do
      assert %{cmd_latest: %Sally.Command{acked: false, refid: refid} = cmd} = ctx
      assert %{dev_alias: %Sally.DevAlias{} = dev_alias} = ctx
      assert %Sally.Command{acked: false} = Sally.Command.save(cmd)
      assert Sally.Command.busy?(cmd)
      assert Sally.Command.busy(dev_alias)
      assert Sally.Command.busy?(refid)

      acked_cmd = Sally.Command.ack_now(cmd)
      assert %Sally.Command{acked: true, acked_at: %DateTime{}} = acked_cmd

      refute Sally.Command.busy?(dev_alias)
      assert %Sally.Command{acked: true} = Sally.Command.saved(dev_alias)
    end
  end

  describe "Sally.Command.saved_count/0" do
    @tag dev_alias_add: [auto: :pwm, count: 3, cmds: [history: 2, latest: :busy]]
    test "increaases", _ctx do
      assert Sally.Command.saved_count() >= 3
    end
  end

  describe "Sally.Command.status/2" do
    @tag dev_alias_add: [auto: :pwm, count: 3, cmds: [history: 2]]
    test "populates :cmds and :status", ctx do
      assert %{dev_alias: [%Sally.DevAlias{} | _] = dev_aliases} = ctx

      %{name: name} = Sally.DevAliasAid.random_pick(dev_aliases)

      status = Sally.Command.status(name, [])

      assert %Sally.DevAlias{cmds: [%Sally.Command{id: id}], status: %{id: id}} = status
    end

    @tag dev_alias_add: [auto: :pwm, count: 3, cmds: [history: 100]]
    test "result is same using DevAlias join query or Command query", ctx do
      assert %{dev_alias: [%Sally.DevAlias{} | _] = dev_aliases} = ctx

      %{name: name} = dev_alias = Sally.DevAliasAid.random_pick(dev_aliases)

      latest_cmd = Sally.Command.latest_cmd(dev_alias)
      dev_alias = Sally.Command.status(name, [])

      assert %Sally.Command{id: cmd_id} = latest_cmd
      assert %Sally.DevAlias{cmds: [%Sally.Command{id: ^cmd_id}]} = dev_alias
    end
  end

  describe "Sally.Command elapsed" do
    @tag skip: true
    @tag output: false
    @tag dev_alias_add: [auto: :pwm, count: 3, cmds: [history: 100]]
    test "status/2 vs. status_from_db2", ctx do
      assert %{dev_alias: [%Sally.DevAlias{} | _] = dev_aliases} = ctx

      dev_alias = Sally.DevAliasAid.random_pick(dev_aliases)

      opts = [dev_alias.name, []]
      {fastest, da1} = Duration.measure(Sally.Command, :status, opts)
      {slowest, da2} = Duration.measure(Sally.Command, :status_from_db, opts)

      fastest_ms = Duration.to_milliseconds(fastest) |> Float.round(2)
      slowest_ms = Duration.to_milliseconds(slowest) |> Float.round(2)

      assert fastest_ms < slowest_ms

      assert %Sally.DevAlias{cmds: [%{cmd: match_cmd}]} = da1
      assert %Sally.DevAlias{cmds: [%{cmd: ^match_cmd}]} = da2

      if ctx.output do
        fastest = to_string(fastest_ms) |> String.pad_leading(6)
        slowest = to_string(slowest_ms) |> String.pad_leading(6)

        header = [ctx.describe, " [line: ", to_string(ctx.line), "]"]

        [status: fastest, status_from_db: slowest]
        |> Enum.map(fn {func, ms} ->
          func = to_string(func) |> String.pad_leading(14, " ")
          ["\n", func, ": ", ms, " ms"]
        end)
        |> then(fn lines -> ["\n", header, lines, "\n"] end)
        |> IO.puts()
      end
    end
  end
end
