defmodule Sally.DeviceTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_device: true

  setup [:host_add, :device_add, :dev_alias_add]

  describe "Sally.Device.cleanup/1" do
    @tag skip: true
    test "deletes devices, aliases, commands and datapoints using opts" do
      opts = [hours: -24]

      cleanup_map = Sally.Device.cleanup(opts)

      assert map_size(cleanup_map) == 0 or map_size(cleanup_map) > 1
    end
  end

  describe "Sally.Device.cleanup_query/1" do
    @tag dev_alias_add: [auto: :ds]
    test "returns query with shift opts applied", ctx do
      %{dev_alias: %{device_id: want_device_id}} = ctx
      query = Sally.Device.cleanup_query(milliseconds: -1)
      device_ids = Sally.Repo.all(query)
      assert is_list(device_ids)

      assert Enum.any?(device_ids, &match?(%{id: ^want_device_id}, &1))
    end
  end

  describe "Sally.Device.find/1" do
    @tag host_add: [], device_add: [auto: :pwm]
    test "finds devices of a specific family", ctx do
      assert %{device: %{id: id}} = ctx

      family = "pwm"
      devices = Sally.Device.find(family: family)

      assert Enum.count(devices) >= 1
      assert Enum.all?(devices, &match?(%{family: ^family}, &1))
      assert %{id: ^id} = Enum.find(devices, &match?(%{id: ^id}, &1))
    end

    # NOTE: ensure there is at least one mutable device
    @tag dev_alias_add: [auto: :pwm]
    test "finds mutable devices", ctx do
      %{device: %{id: id}} = ctx

      mutable? = true
      devices = Sally.Device.find(mutable: mutable?)

      assert Enum.count(devices) >= 1
      assert Enum.all?(devices, &match?(%{mutable: ^mutable?}, &1))
      assert %{id: ^id} = Enum.find(devices, &match?(%{id: ^id}, &1))
    end

    # NOTE: ensure there is at least one immutable device
    @tag dev_alias_add: [auto: :ds]
    test "finds immutable devices", ctx do
      %{device: %{id: id}} = ctx

      mutable? = false
      devices = Sally.Device.find(mutable: mutable?)

      assert Enum.count(devices) >= 1
      assert Enum.all?(devices, &match?(%{mutable: ^mutable?}, &1))
      assert %{id: ^id} = Enum.find(devices, &match?(%{id: ^id}, &1))
    end
  end
end
