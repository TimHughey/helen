defmodule SallyDevAliasAlignTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_dev_alias_align: true

  setup [:dev_alias_add]

  describe "Sally.DevAlias.align_status/1" do
    @tag dev_alias_add: [auto: :pwm, count: 3, cmds: [history: 1]]
    test "makes no change when the reported cmd is the same as local cmd", ctx do
      assert %{device: %Sally.Device{} = device, dev_alias: [_ | _] = dev_aliases} = ctx
      dev_alias = Sally.DevAliasAid.random_pick(dev_aliases)

      data = %{pins: Sally.CommandAid.make_pins(device, %{pins: [:from_status]})}
      dispatch = %{data: data, recv_at: Timex.now()}

      aligned = Sally.DevAlias.align_status(dev_alias, dispatch)

      assert {:aligned, <<_::binary>>} = aligned
    end

    @tag dev_alias_add: [auto: :pwm, count: 3, cmds: [history: 3, latest: :busy]]
    test "does nothing when Sally.DevAlias has a busy command", ctx do
      assert %{device: %Sally.Device{} = device, dev_alias: [_ | _] = dev_aliases} = ctx
      dev_alias = Enum.find(dev_aliases, &Sally.Command.busy?(&1))
      assert %Sally.DevAlias{} = dev_alias

      assert Sally.Command.busy?(dev_alias)

      # NOTE: Sally.CommandAid.make_pins/2 creates a random pin cmd when a Sally.Command is busy
      pins = Sally.CommandAid.make_pins(device, %{pins: [:from_status]})
      dispatch = %{data: %{pins: pins}, recv_at: Timex.now()}

      busy = Sally.DevAlias.align_status(dev_alias, dispatch)

      assert {:busy, {:tracked, pid}} = busy
      assert Process.alive?(pid)
    end

    @tag dev_alias_add: [auto: :pwm, count: 3]
    @tag capture_log: true
    test "handles Sally.DevAlias without cmd history", ctx do
      assert %{device: %Sally.Device{} = device, dev_alias: [_ | _] = dev_aliases} = ctx
      dev_alias = Sally.DevAliasAid.random_pick(dev_aliases)

      data = %{pins: Sally.CommandAid.make_pins(device, %{pins: [:random]})}
      dispatch = %{data: data, recv_at: Timex.now()}

      assert %Sally.Command{} = Sally.DevAlias.align_status(dev_alias, dispatch)
    end

    @tag dev_alias_add: [auto: :pwm, count: 3, cmds: [history: 1]]
    @tag capture_log: true
    test "corrects cmd mismatch", ctx do
      assert %{device: %Sally.Device{} = device, dev_alias: [_ | _] = dev_aliases} = ctx
      dev_alias = Sally.DevAliasAid.random_pick(dev_aliases)

      data = %{pins: Sally.CommandAid.make_pins(device, %{pins: [:random]})}
      dispatch = %{data: data, recv_at: Timex.now()}

      assert %Sally.Command{acked: true} = Sally.DevAlias.align_status(dev_alias, dispatch)
    end
  end
end
