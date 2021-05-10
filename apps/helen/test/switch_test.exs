defmodule SwitchTest do
  @moduledoc false
  use ExUnit.Case

  use HelenTestShould

  alias Switch.DB.{Alias, Device}
  alias SwitchTestHelper, as: Helper

  @moduletag :switch
  @wait_for_ack [wait_for_ack: true]

  setup_all do
    on_exit(fn -> Switch.cmd_counts_reset([:orphaned, :errors]) end)

    Helper.delete_all_devices()

    # populate keys we always want in the ctx then make the default device
    ctx = %{type: "switch", execute_rc: %{}, alias_create: [], setup_all: true} |> Helper.make_device()

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
    per_test = [:make_alias, :pio, :name, :cmd_map, :freshen, :freshen_rc, :roundtrip_rc]

    ctx
    |> debug("START OF SETUP CTX")
    |> Helper.make_device_if_needed()
    |> Helper.load_device_if_needed()
    |> setup_ctx()
    |> Helper.freshen_auto()
    |> Helper.execute_cmap()
    |> debug("END OF SETUP CTX")
    |> Map.drop(per_test)
  end

  @tag make_alias: true
  @tag pio: :any
  @tag name: "Create Switch Alias"
  test "can create a Switch alias", ctx do
    x = Switch.alias_find(ctx.name)
    should_be_struct(x, Alias)

    %Alias{name: alias_name} = x
    fail = pretty("alias name should be #{alias_name} == #{ctx.name}")
    assert alias_name == ctx.name, fail
  end

  # @tag device: "switch/simulated-alpha"
  @tag make_alias: true
  @tag pio: :any
  @tag name: "Execute With Ack"
  @tag freshen: true
  @tag cmd_map: %{cmd: "on", opts: [ack: :immediate]}
  test "can Switch execute a cmd map and ack", ctx do
    should_be_ok_tuple(ctx.execute_rc)

    {_rc, exec_details} = ctx.execute_rc

    should_contain(exec_details, cmd: "on")

    status = Switch.status(ctx.name)

    should_be_non_empty_map(status)
    should_contain(status, cmd: "on")
  end

  @tag device: "switch/simulated-beta"
  @tag make_alias: true
  @tag pio: :any
  @tag freshen: true
  @tag name: "Execute Pending Test"
  # NOTE: above name is automatically added to the cmd map during test setup
  @tag cmd_map: %{cmd: "on", opts: @wait_for_ack}
  test "can Switch detect pending cmds", ctx do
    cmd_map = %{cmd: "on", name: ctx.name}
    execute_rc = Switch.execute(cmd_map)
    should_be_tuple_with_rc(execute_rc, :pending)

    {:pending, exec_details} = execute_rc

    should_contain_key(exec_details, :refid)

    status = Switch.status(ctx.name)
    should_be_status_map(status)
    should_contain_key(status, :pending)
  end

  @tag device: "switch/simulated-beta"
  @tag make_alias: true
  @tag pio: :any
  @tag name: "Names Test"
  test "can Switch get all alias names", ctx do
    names = Switch.names()
    should_be_non_empty_list(names)
    should_contain_value(names, ctx.name)
  end

  @tag device: "switch/simulated-beta"
  @tag make_alias: true
  @tag pio: :any
  @tag name: "Command Count Test"
  @tag freshen: true
  @tag cmd_map: %{cmd: "on", opts: [ack: :host]}
  test "can Switch get command counts" do
    cmds = Switch.cmd_counts()
    fail = pretty("cmd count should be > 0", cmds)
    assert cmds > 0, fail

    tracked = Switch.cmds_tracked()
    fail = pretty("cmds tracked should be > 0", tracked)
    assert tracked > 0, fail
  end

  # @tag device: "switch/simulated3-gamma"
  # @tag make_alias: true
  # @tag pio: :any
  # @tag name: "Custom Command Test"
  # @tag cmd_map: %{
  #        cmd: "Extensive Cmd Test",
  #        type: "random",
  #        min: 256,
  #        max: 1024,
  #        primes: 35,
  #        step_ms: 55,
  #        step: 13,
  #        priority: 7,
  #        opts: [wait_for_ack: true]
  #      }
  # test "can Switch execute an extensive cmd map", ctx do
  #   status = Switch.status(ctx.name)
  #   should_be_non_empty_map(status)
  #   should_be_cmd_equal(status, ctx.cmd_map.cmd)
  # end

  # @tag skip: true
  @tag device: "switch/blackhole"
  @tag host: "ruth.blackhole"
  @tag ttl_ms: 3000
  @tag make_alias: true
  @tag pio: :any
  @tag name: "Black Hole"
  @tag cmd_map: %{cmd: "on"}
  test "can Switch broom handle orphans", ctx do
    # indirect test of :ignore_pending
    Switch.execute(%{name: ctx.name, cmd: "off", opts: [ignore_pending: true]})

    status = Switch.status(ctx.name, ignore_pending: true)
    should_be_non_empty_map(status)

    orphan_check = fn
      %{cmd_last: %{orphan: true}} -> true
      _ -> false
    end

    for _x <- 1..1300, reduce: :start do
      :start -> Process.sleep(50) == :ok && false
      false -> Switch.status(ctx.name) |> orphan_check.()
      true -> true
    end

    status_final = Switch.status(ctx.name)
    fail = pretty("cmd_last should indicate orphan", status_final)
    assert status_final |> orphan_check.(), fail
  end

  @tag device: "switch/simulated-ttl"
  @tag ttl_ms: 51
  @tag make_alias: true
  @tag pio: :any
  @tag name: "TTL Expired Check"
  @tag cmd_map: %{cmd: "on", opts: @wait_for_ack}
  test "can Switch detect ttl expired", ctx do
    Process.sleep(55)

    status = Switch.status(ctx.name)
    should_be_status_map(status)
    should_be_cmd_equal(status, "unknown")
    should_contain_key(status, :ttl_expired)
    should_contain_key(status, :ttl_elapsed_ms)
    should_contain_key(status, :ttl_ms)
  end

  @tag device: "switch/simulated-delta"
  @tag make_alias: true
  @tag pio: :any
  @tag name: "Status Test"
  @tag ttl_ms: 5000
  @tag cmd_map: %{cmd: "on", opts: [wait_for_ack: true]}
  test "can get Switch status", ctx do
    should_be_non_empty_map(ctx.execute_rc)

    status = Switch.status(ctx.name)
    should_be_non_empty_map(status)

    should_be_cmd_equal(status, ctx.cmd_map.cmd)
    should_not_be_ttl_expired(status)
    should_not_be_pending(status)
  end

  @tag device: "switch/simulated-epsilon"
  @tag make_alias: true
  @tag pio: :any
  @tag name: "Delete Test"
  test "can Switch delete an alias (with bonus duplicate alias test)", ctx do
    Switch.on(ctx.name, @wait_for_ack)

    alias_actual = Switch.alias_find(ctx.name)

    res = Switch.alias_create(ctx.device_actual.id, ctx.name, alias_actual.pio)
    should_contain_key(res, :exists)

    res = Switch.delete(ctx.name)
    should_be_ok_tuple_with_val(res, ctx.name)
  end

  @tag device: "switch/simulated-epsilon"
  @tag make_alias: true
  @tag pio: :any
  @tag name: "Names Test"
  test "can Switch get alias names (with bonus off/2 test)", ctx do
    Switch.off(ctx.name, @wait_for_ack)

    all_names = Switch.names()
    should_be_non_empty_list(all_names)

    pattern_names = Switch.names_begin_with("")
    should_be_non_empty_list(pattern_names)
  end

  @tag device: "switch/simulated-epsilon"
  @tag make_alias: true
  @tag pio: :any
  @tag name: "GenNotify Basic Test"
  test "can Switch get the GenNotify server state, restart and the notify map", ctx do
    Switch.on(ctx.name, @wait_for_ack)

    state = Switch.notify_state()
    should_be_non_empty_map(state)

    restart_rc = Switch.notify_restart()
    should_be_ok_tuple(restart_rc)

    notify_map = Switch.notify_map()
    fail = pretty("should be a map", notify_map)
    assert is_map(notify_map), fail
  end

  @tag device: "switch/simulated-notify"
  @tag make_alias: true
  @tag pio: :any
  @tag name: "GenNotify Notification Test"
  @tag cmd_map: %{cmd: "on", opts: @wait_for_ack}
  test "can Switch notify when device changes", ctx do
    rc = Switch.notify_register(name: ctx.name, notify_interval: "PT1S")
    should_be_ok_tuple(rc)

    Switch.off(ctx.name)

    recv_notification = fn ->
      receive do
        {:notify, _category, _item} = recv -> recv
        recv -> recv
      after
        5000 -> :timeout
      end
    end

    recv = recv_notification.()
    fail = pretty("should be a three element tuple {:notify, :gennotify, %Alias{}}", recv)
    assert {:notify, :gennotify, %Alias{}} = recv, fail
  end

  test "can Switch Broom report metrics" do
    rc = Switch.DB.Command.report_metrics(interval: "PT30S")

    should_be_ok_tuple_with_val(rc, "PT30S")
  end

  defp debug(ctx, msg) when is_map_key(ctx, :debug) do
    [msg, "\n--->", pretty(ctx), "\n<---\n"] |> IO.iodata_to_binary() |> IO.puts()

    ctx
  end

  defp debug(ctx, _msg), do: ctx
end
