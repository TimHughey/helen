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

      tracked_cmd = Sally.Command.track(cmd, [])
      assert %Sally.Command{track: tracked} = tracked_cmd
      assert {:tracked, pid} = tracked
      assert is_pid(pid) and Process.alive?(pid)

      tracked_info = Sally.Command.tracked_info(refid)
      assert %Sally.Command{} = tracked_info

      track = %Alfred.Track{tracked_info: tracked_info}

      assert %Sally.Command{cmd: acked_cmd} = cmd = Sally.Command.track_timeout(track)

      assert %{acked: true, orphaned: true} = cmd
      assert %{acked_at: %DateTime{}, rt_latency_us: rt_us} = cmd
      assert %{dev_alias_id: ^dev_alias_id} = cmd

      assert is_integer(rt_us) and rt_us > 100

      assert %{rc: rc, detail: %{cmd: ^acked_cmd}} = Alfred.status(name)
      assert {:timeout, ms} = rc
      assert ms > 1
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
      assert %{dev_alias: dev_aliases, cmd_latest: cmds} = ctx

      dev_alias = Sally.DevAliasAid.random_pick(dev_aliases)
      assert %{name: name} = dev_alias

      %{id: cmd_id} = find_latest_cmd(cmds, dev_alias)

      status = Sally.Command.status(name, [])

      assert %Sally.DevAlias{name: ^name, status: %{id: ^cmd_id}} = status
    end

    @tag dev_alias_add: [auto: :pwm, count: 3, cmds: [history: 100]]
    test "result is same using DevAlias join query or Command query", ctx do
      assert %{dev_alias: [%Sally.DevAlias{} | _] = dev_aliases} = ctx

      %{name: name} = dev_alias = Sally.DevAliasAid.random_pick(dev_aliases)

      latest_cmd = Sally.Command.latest_cmd(dev_alias)
      dev_alias = Sally.Command.status(name, [])

      assert %Sally.Command{id: cmd_id} = latest_cmd
      assert %Sally.DevAlias{status: %{id: ^cmd_id}} = dev_alias
    end

    @tag dev_alias_add: [auto: :pwm, cmds: [history: 3]]
    test "preloads device and host", ctx do
      assert %{dev_alias: %{name: name}} = ctx

      query = Sally.Command.status_query(name, preload: :device_and_host)

      dev_alias = Sally.Repo.one(query)

      assert %{device: %Sally.Device{host: %Sally.Host{}}} = dev_alias
    end
  end
end
