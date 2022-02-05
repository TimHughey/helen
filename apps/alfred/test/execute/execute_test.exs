defmodule Alfred.ExecuteTest do
  use ExUnit.Case, async: true
  use Alfred.TestAid

  @moduletag alfred: true, alfred_execute: true

  setup [:equipment_add, :sensor_add, :name_add]

  defmacrop get_name_from_ctx do
    quote do
      possible = Map.take(var!(ctx), [:sensor, :equipment, :name]) |> Map.values()
      assert [name | _] = possible

      name
    end
  end

  describe "Alfred.execute/2" do
    @tag name_add: [type: :unk]
    test "handles unknown name", ctx do
      name = get_name_from_ctx()

      execute = Alfred.execute([name: name, cmd: "on"], [])

      assert %Alfred.Execute{name: ^name, rc: :not_found, detail: :none} = execute

      assert Alfred.execute_to_binary(execute) =~ "NOT_FOUND"
    end

    @tag equipment_add: [cmd: "off"]
    test "handles cmd equal to status", ctx do
      name = get_name_from_ctx()

      execute = Alfred.execute(name: name, cmd: "off")
      assert %Alfred.Execute{rc: :ok, cmd: cmd, detail: %{cmd: cmd}, name: ^name} = execute

      assert Alfred.execute_to_binary(execute) =~ "OK {off} [mutable"
    end

    @tag equipment_add: [cmd: "off"]
    test "cmd different than status", ctx do
      name = get_name_from_ctx()
      execute_args = [name: name, cmd: "on"]

      execute = Alfred.execute(execute_args, [])

      assert %Alfred.Execute{cmd: "on" = cmd, rc: :busy} = execute
      assert %Alfred.Execute{__raw__: %Alfred.DevAlias{}} = execute
      assert %Alfred.Execute{detail: detail, name: ^name} = execute
      assert %{cmd: ^cmd, refid: refid} = detail

      assert Alfred.execute_to_binary(execute) =~ "BUSY {on} @"

      assert Alfred.Track.tracked?(refid)

      assert :ok == Alfred.Command.release(refid, [])

      assert [errors: _, released: _, timeout: _, tracked: tracked] = Alfred.Track.Metrics.counts()
      assert tracked > 0
    end

    @tag equipment_add: [cmd: "off", busy: true]
    test "handles busy status", ctx do
      name = get_name_from_ctx()

      execute_args = [name: name, cmd: "on"]

      execute = Alfred.execute(execute_args, [])
      assert %Alfred.Execute{rc: :busy, cmd: "off", detail: detail, name: ^name} = execute

      assert %{cmd: "off", refid: <<_::binary>>, sent_at: %DateTime{}} = detail

      assert Alfred.execute_to_binary(execute) =~ "BUSY {off} @"
    end

    @tag equipment_add: [cmd: "off", timeout: true]
    test "handles timeout status", ctx do
      name = get_name_from_ctx()

      execute_args = [name: name, cmd: "on"]

      execute = Alfred.execute(execute_args, [])
      assert %Alfred.Execute{rc: rc, cmd: "off", detail: detail, name: ^name} = execute

      assert {:timeout, ms} = rc
      assert ms > 10
      assert %{cmd: "off", refid: <<_::binary>>, sent_at: %DateTime{}} = detail

      assert Alfred.execute_to_binary(execute) =~ ~r/TIMEOUT \+\d+ms \[\w+/
    end

    @tag equipment_add: [cmd: "off", expired_ms: 10]
    test "handles ttl_expired status", ctx do
      name = get_name_from_ctx()

      execute_args = [name: name, cmd: "on"]

      execute = Alfred.execute(execute_args)
      assert %Alfred.Execute{rc: rc, cmd: "unknown", detail: detail, name: ^name} = execute

      assert {:ttl_expired, ms} = rc
      assert ms > 10
      assert :none = detail

      assert Alfred.execute_to_binary(execute) =~ ~r/TTL_EXPIRED \+\d+ms \[\w+/
    end

    @tag equipment_add: [cmd: "off"]
    test "honors force: true ", ctx do
      name = get_name_from_ctx()

      cmd = "off"
      execute_args = [name: name, cmd: cmd]

      execute = Alfred.execute(execute_args, force: true)
      assert %Alfred.Execute{rc: :busy, cmd: ^cmd, detail: detail, name: ^name} = execute

      assert %{cmd: ^cmd, acked: false, refid: <<_::binary>>} = detail
      assert %{sent_at: %DateTime{}, track: {:ok, pid}} = detail
      assert is_pid(pid) and Process.alive?(pid)

      assert Alfred.execute_to_binary(execute) =~ "BUSY {off} @"
    end
  end
end
