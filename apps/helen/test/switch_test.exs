defmodule HelenSwitchTest do
  use ExUnit.Case, async: true

  import HelenTestHelpers, only: [pretty: 1, pretty: 2]

  @moduletag :helen_switch

  @states_count 12
  @states_default for pio <- 0..@states_count, do: %{state: false, pio: pio}

  setup_all do
    import Switch.DB.Device, only: [find: 1]

    import SwitchTestHelper,
      only: [delete_default_device: 0, device_default: 0, make_switch: 1]

    delete_default_device()

    res =
      make_switch(
        device: device_default(),
        states: @states_default
      )

    fail = "make_switch response should be a map#{pretty(res)}"
    assert is_map(res), fail

    fail = "messages dispatched should be > 0#{pretty(res)}"
    assert get_in(res, [:messages_dispatched]) > 0, fail

    device_actual = find(device_default())

    fail = "should have found newly created device#{pretty(device_actual)}"
    assert is_struct(device_actual), fail

    on_exit(fn -> delete_default_device() end)

    {:ok, %{device_actual: device_actual, device: device_actual.device}}
  end

  def setup_ctx(ctx) do
    import SwitchTestHelper, only: [execute_cmd: 1, freshen: 1, make_alias: 1]

    ctx = if ctx[:make_alias], do: make_alias(ctx), else: ctx
    ctx = if ctx[:execute], do: execute_cmd(ctx), else: ctx
    ctx = if ctx[:freshen], do: freshen(ctx), else: ctx

    alias_name = ctx[:alias_name]

    if is_binary(alias_name) do
      status = Switch.status(alias_name)

      fail = "status should be a map#{pretty(status)}"
      assert is_map(status), fail

      new_ctx = %{alias_name: alias_name, status: status}
      Map.merge(ctx, new_ctx)
    else
      ctx
    end
  end

  setup ctx do
    {:ok, setup_ctx(ctx)}
  end

  test "can create a basic switch", %{device_actual: device} do
    import SwitchTestHelper, only: [device_default: 0]
    fail = "device should be a struct#{pretty(device)}"
    assert %Switch.DB.Device{} = device, fail

    fail = "newly created device name does not match#{pretty(device)}"
    %Switch.DB.Device{device: dev_name} = device
    assert dev_name == device_default(), fail
  end

  test "can get all switch aliases" do
    count = Switch.aliases(:count)
    fail = "count of switch aliases should be > 0#{pretty(count)}"
    assert count > 0, fail

    raw = Switch.aliases(:raw)
    fail = "Switch.aliases(:raw) should return a non-empty list#{pretty(raw)}"
    assert is_list(raw), fail
    refute [] == raw, fail
    assert is_map(hd(raw)), fail

    fail = "list entries should contain :name#{pretty(raw)}"
    assert is_map_key(hd(raw), :name), fail
  end

  test "can get devices that begin with a pattern" do
    devices = Switch.devices_begin_with("")

    fail = pretty("should be a list", devices)
    assert is_list(devices), fail
  end

  @tag make_alias: true
  @tag pio: :any
  @tag alias_name: "Status Test"
  @tag execute: %{cmd: :off, name: "Status Test"}
  @tag ack: true
  test "can get switch status", %{status: status, alias_name: name} do
    fail = "cmd should be :off#{pretty(status)}"
    assert :off == status[:cmd], fail

    fail = ":name should be in status#{pretty(status)}"
    assert name == status[:name], fail

    fail = "should not be ttl expired"
    refute is_map_key(status, :ttl_expired), fail
  end

  @tag make_alias: true
  @tag pio: :any
  @tag alias_name: "Freshen Test"
  @tag freshen: true
  test "can freshen an existing switch", %{status: status, alias_name: name} do
    fail = ":name should be in status#{pretty(status)}"
    assert name == status[:name], fail

    fail = "should not be ttl expired"
    refute is_map_key(status, :ttl_expired), fail
  end

  @tag make_alias: true
  @tag pio: :any
  @tag alias_name: "Switch Execute With Ack"
  @tag execute: %{cmd: :on, name: "Switch Execute With Ack"}
  @tag ack: true
  test "can switch execute a cmd map and ack", %{
    alias_name: name,
    execute_rc: execute_rc
  } do
    fail = "execute_rc should be a list#{pretty(execute_rc)}"
    assert is_list(execute_rc), fail

    fail = "execute_rc should include the refid#{inspect(execute_rc)}"
    refid = get_in(execute_rc, [:refid])
    assert refid, fail

    fail = "refid should be acked#{pretty(execute_rc)}"
    assert Switch.acked?(refid), fail

    status = Switch.status(name)

    fail = "status should be a map#{pretty(status)}"
    assert is_map(status), fail

    fail = "cmd should be :on#{pretty(status)}"
    assert :on == status[:cmd], fail
  end

  @tag make_alias: true
  @tag pio: :any
  @tag alias_name: "Status Test TTL Expired"
  @tag ttl_ms: 100
  test "can get switch status with expired ttl", %{alias_name: name} do
    wait_for_ttl = fn ->
      for _i <- 1..200, reduce: false do
        false ->
          case Switch.status(name) do
            %{ttl_expired: true} ->
              true

            _ ->
              Process.sleep(100)
              false
          end

        true ->
          true
      end
    end

    fail = "should have seen :ttl_expired"
    assert wait_for_ttl.(), fail
  end

  test "can get all device names" do
    res = Switch.DB.Device.devices()

    fail = "should be a list#{pretty(res)}"
    assert is_list(res), fail
    refute [] == res, fail
  end
end
