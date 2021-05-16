defmodule SensorTest do
  @moduledoc false
  use ExUnit.Case

  use HelenTestShould

  alias Sensor.DB.{Alias, Device}
  alias SensorTestHelper, as: Helper

  @moduletag :sensor

  setup_all do
    Helper.delete_all_devices()

    # populate keys we always want in the ctx then make the default device
    ctx = %{type: "sensor", execute_rc: %{}, alias_create: [], setup_all: true} |> Helper.make_device()

    should_contain_key(ctx, :device)

    device_actual = Device.find(ctx.device)
    should_be_struct(device_actual, %Device{})

    ctx |> Map.drop([:device, :make_device, :setup_all]) |> RuthSim.default_device()
  end

  def setup_ctx(ctx) do
    {rc, ctx} = Repo.transaction(fn -> Helper.make_alias(ctx) end, [])

    fail = pretty("setup ctx transaction should be rc == #{inspect(rc)}", ctx)
    assert :ok == rc, fail

    ctx
  end

  setup ctx do
    per_test = [:make_alias, :name, :freshen, :freshen_rc, :roundtrip_rc]

    ctx
    |> debug("START OF SETUP CTX")
    |> Helper.make_device_if_needed()
    |> Helper.load_device_if_needed()
    |> setup_ctx()
    # |> Helper.freshen_auto()
    |> Helper.send_datapoints()
    |> debug("END OF SETUP CTX")
    |> Map.drop(per_test)
  end

  # @tag debug: true
  @tag make_alias: true
  @tag name: "Create Sensor Alias"
  test "can create a Sensor alias", ctx do
    x = Sensor.alias_find(ctx.name)
    should_be_struct(x, Alias)

    %Alias{name: alias_name} = x
    fail = pretty("alias name should be #{alias_name} == #{ctx.name}")
    assert alias_name == ctx.name, fail
  end

  @tag device: "sensor/sim-names"
  @tag make_alias: true
  @tag name: "Sensor Names Test"
  @tag datapoints: {:temp_c, 25}
  test "can Sensor get all alias names", ctx do
    names = Sensor.names()
    should_be_non_empty_list(names)
    should_contain_value(names, ctx.name)

    should_be_non_empty_list(ctx.datapoints_sent)
  end

  @tag delete_test: true
  @tag device: "sensor/sim-delete"
  @tag make_alias: true
  @tag name: "Sensor Delete Test"
  @tag datapoints: {:temp_c, 100}
  test "can Sensor get delete a name", ctx do
    res = Sensor.delete(ctx.name)

    should_be_ok_tuple(res)

    {:ok, list} = res

    should_be_non_empty_list(list)
    should_contain(list, name: "Sensor Delete Test")
    should_contain(list, datapoints: 100)

    available = Alfred.available(ctx.name)
    fail = pretty("Alfred should return \"#{ctx.name}\" is available", available)
    assert available, fail

    exists = Sensor.exists?(ctx.name)
    fail = pretty("Sensor \"#{ctx.name}\" should not exist", exists)
    refute exists, fail
  end

  @tag device: "sensor/sim-status-tempc"
  @tag make_alias: true
  @tag name: "Sensor TempC Status Test"
  @tag datapoints: {:temp_c, 25}
  @tag ttl_ms: 1000
  test "can Sensor can get TempC status (ttl ok)", ctx do
    res = Sensor.status(ctx.name)
    should_contain(res, count: 25)
    should_contain(res, name: ctx.name)
    should_contain(res, ttl_ms: ctx.ttl_ms)
    should_contain(res, values: [:count, :temp_c])
    should_contain_key(res, :temp_c)
  end

  @tag device: "sensor/sim-status-relhum"
  @tag make_alias: true
  @tag name: "Sensor RelHum Status Test"
  @tag datapoints: {:relhum, 25}
  @tag ttl_ms: 1000
  test "can Sensor can get RelHum status (ttl ok)", ctx do
    res = Sensor.status(ctx.name)
    should_contain(res, count: 25)
    should_contain(res, name: ctx.name)
    should_contain(res, ttl_ms: ctx.ttl_ms)
    should_contain(res, values: [:count, :relhum, :temp_c])
    should_contain_key(res, :temp_c)
    should_contain_key(res, :relhum)
  end

  @tag device: "sensor/sim-dup-alias"
  @tag make_alias: true
  @tag name: "Sensor Duplicate Alias Test"
  @tag datapoints: {:relhum, 25}
  @tag ttl_ms: 1000
  test "can Sensor.alias_create/2 handle edge cases", ctx do
    # ensure the alias was created during setup and has datapoints
    res = Alfred.status(ctx.name)
    should_contain(res, count: 25)
    should_contain(res, name: ctx.name)

    # duplicate name test
    res = Sensor.alias_create(ctx.device, ctx.name)
    should_be_tuple_with_rc(res, :exists)

    {:exists, details} = res
    should_contain(details, name: ctx.name)
    should_contain_key(details, :alfred)

    # attempt to create alias for non-existant device
    res = Sensor.alias_create("sensor/foobar", "Unknown Device Test")
    should_be_tuple_with_rc(res, :not_found)

    {:not_found, details} = res
    should_contain(details, device: "sensor/foobar")

    # attempt to create alias that exists in database but not in Alfred
    Alfred.delete(ctx.name)

    res = Sensor.alias_create(ctx.device, ctx.name)
    should_be_tuple_with_rc(res, :exists)

    {:exists, details} = res
    should_contain(details, name: ctx.name)
    should_contain(details, device: ctx.device)
  end

  @tag device: "sensor/sim-stale-alias"
  @tag make_alias: true
  @tag name: "Sensor Stale Device Test"
  @tag datapoints: {:relhum, 25}
  @tag ttl_ms: 1000
  test "does Sensor.alias_create/2 refuse to create alias for stale device", ctx do
    # ensure the alias was created during setup and has datapoints
    res = Alfred.status(ctx.name)
    should_contain(res, count: 25)
    should_contain(res, name: ctx.name)

    # delete the alias so we can create a new one
    Sensor.delete(ctx.name)

    # duplicate name test
    res = Sensor.alias_create(ctx.device, ctx.name, device_stale_after: "PT0.001S")
    should_be_tuple_with_rc(res, :device_stale)

    {:device_stale, details} = res
    should_contain(details, device: ctx.device)
  end

  # @tag device: "sensor/simulated-ttl"
  # @tag ttl_ms: 51
  # @tag make_alias: true
  # @tag name: "TTL Expired Check"
  # @tag cmd_map: %{cmd: "on", opts: @wait_for_ack}
  # test "can Sensor detect ttl expired", ctx do
  #   Process.sleep(55)
  #
  #   status = Sensor.status(ctx.name)
  #   should_be_status_map(status)
  #   should_be_cmd_equal(status, "unknown")
  #   should_contain_key(status, :ttl_expired)
  #   should_contain_key(status, :ttl_elapsed_ms)
  #   should_contain_key(status, :ttl_ms)
  # end

  defp debug(ctx, msg) when is_map_key(ctx, :debug) do
    [msg, "\n--->", pretty(ctx), "\n<---\n"] |> IO.iodata_to_binary() |> IO.puts()

    ctx
  end

  defp debug(ctx, _msg), do: ctx
end
