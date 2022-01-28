defmodule Sally.CommandAidTest do
  use ExUnit.Case, aync: true
  use Sally.TestAid

  @moduletag sally: true, sally_command_aid: true

  setup [:dev_alias_add]

  describe "Sally.CommandAid.make_pins/1" do
    @tag dev_alias_add: [auto: :pwm, count: 3, cmds: [history: 1]]
    test "creates a pin cmd list for a device using the aliases statius", ctx do
      assert %{device: device} = ctx

      opts_map = %{pins: [:from_status]}
      pin_list = Sally.CommandAid.make_pins(device, opts_map)

      assert [[0, <<_::binary>>], [1, <<_::binary>>], [2, <<_::binary>>], [3, "off"]] = pin_list
    end
  end

  describe "Sally.CommandAid.historical/1" do
    @tag dev_alias_add: [auto: :pwm, cmds: [history: 3, latest: :busy]]
    test "saves and tracks cmd latest when busy (aka busy) for one DevAlias", ctx do
      assert %{cmd_latest: %Sally.Command{} = cmd} = ctx
      assert %{dev_alias: %Sally.DevAlias{} = dev_alias} = ctx

      assert Sally.Command.busy?(cmd)
      assert Sally.Command.busy?(dev_alias)

      tracked_info = Sally.Command.tracked_info(cmd.refid)
      assert %Sally.Command{} = tracked_info
    end

    @tag dev_alias_add: [auto: :pwm, count: 3, cmds: [history: 3, latest: :busy]]
    test "saves and tracks cmd latest when busy (aka busy) for many DevAlias", ctx do
      assert %{cmd_latest: [%Sally.Command{} | _] = cmds} = ctx
      assert %{dev_alias: [%Sally.DevAlias{} | _] = dev_aliases} = ctx

      Enum.each(cmds, fn cmd -> assert Sally.Command.busy?(cmd) end)
      Enum.each(dev_aliases, fn dev_alias -> assert Sally.Command.busy?(dev_alias) end)

      Enum.each(cmds, fn cmd ->
        tracked_info = Sally.Command.tracked_info(cmd.refid)
        assert %Sally.Command{} = tracked_info
      end)
    end
  end
end
