defmodule Sally.Synchronous.DevAliasTest do
  use ExUnit.Case
  use Sally.TestAid

  @moduletag sally: true, sally_synchronous_dev_alias: true

  setup_all do
    # always create and setup a host
    {:ok, %{host_add: []}}
  end

  setup [:host_add, :device_add]

  describe "Sally.device_add_alias/1" do
    @tag device_add: [auto: :ds]
    test "creates alias to latest device discovered", ctx do
      assert %{device: %Sally.Device{id: want_dev_id}} = ctx

      opts = [device: :latest, name: Sally.DevAliasAid.unique(:dev_alias)]
      assert %{device_id: ^want_dev_id} = Sally.device_add_alias(opts)
    end
  end
end
