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
end
