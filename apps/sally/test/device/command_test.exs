defmodule SallyCommandTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_command: true

  setup_all do
    # always create and setup a host
    {:ok, %{host_add: [], host_setup: []}}
  end

  setup [:host_add, :host_setup, :device_add, :devalias_add, :devalias_just_saw]
  setup [:command_add, :datapoint_add, :dispatch_add]

  describe "Sally.Command.broom_timeout/1" do
    @tag device_add: [auto: :mcp23008], devalias_add: [], command_add: [cmd: "on"]
    test "acks a command", ctx do
      %{dev_alias: %Sally.DevAlias{id: id} = _dev_alias, command: %Sally.Command{dev_alias_id: id} = command} =
        ctx

      broom = %Alfred.Broom{tracked_info: command}

      assert {:ok, %Sally.Command{acked: true, acked_at: %DateTime{}, orphaned: true, rt_latency_us: rt_us}} =
               Sally.Command.broom_timeout(broom)

      assert is_integer(rt_us) and rt_us > 100
    end
  end
end
