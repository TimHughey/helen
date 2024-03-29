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
    @tag sally_isolated: true
    @tag device_add: [auto: :ds]
    test "creates alias to latest device discovered", ctx do
      assert %{device: %{id: want_dev_id, inserted_at: _inserted_at}} = ctx

      opts = [milliseconds: -30, name: Sally.DevAliasAid.unique(:dev_alias)]
      assert %{device_id: ^want_dev_id} = Sally.device_add_alias(:latest, opts)
    end
  end
end
