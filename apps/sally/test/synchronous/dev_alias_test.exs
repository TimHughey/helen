defmodule Sally.Synchronous.DevAliasTest do
  use ExUnit.Case
  use Sally.TestAid

  @moduletag sally: true, sally_synchronous_dev_alias: true

  setup_all do
    # always create and setup a host
    {:ok, %{host_add: [], host_setup: []}}
  end

  setup [:host_add, :host_setup, :device_add]

  describe "Sally.device_add_alias/1" do
    @tag device_add: [auto: :ds]
    test "creates alias to latest device discovered", %{device: device} do
      opts = [device: :latest, name: Sally.DevAliasAid.unique(:dev_alias)]
      assert %Sally.DevAlias{} = dev_alias = Sally.device_add_alias(opts)

      assert %Sally.DevAlias{device: %Sally.Device{ident: ident}} = Sally.DevAlias.load_device(dev_alias)
      assert ident == device.ident
    end
  end
end
