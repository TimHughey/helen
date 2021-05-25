defmodule BroomTest do
  use ExUnit.Case
  use BroomTestShould

  # setup common ctx keys for map matching / updates
  @moduletag [
    broom: true,
    impl_mod: Broom.Execute,
    device_struct: nil,
    alias_struct: nil,
    alias_name: nil,
    cmd_struct: nil,
    tracker_entry: nil
  ]

  setup_all ctx do
    ctx
  end

  setup ctx do
    ctx
  end

  test "can Broom create a child_spec for the using module", ctx do
    spec = ctx.impl_mod.child_spec(initial: :test)
    should_be_non_empty_map(spec)
    should_contain(spec, id: ctx.impl_mod)
  end

  test "can Broom get counts", ctx do
    res = Broom.via_mod_counts(ctx.impl_mod)
    fail = pretty("should be = %Counts{}", res)
    assert %Broom.Counts{} = res, fail
  end

  test "can Broom reset counts", ctx do
    res = Broom.via_mod_counts_reset(ctx.impl_mod, [:orphaned, :tracked, :not_a_count])
    should_be_tuple(res)
    fail = pretty("should be {:reset, %Counts{}}", res)
    assert :reset == elem(res, 0), fail
    assert %Broom.Counts{} = elem(res, 1), fail
  end

  @tag skip: false
  @tag dump_state: false
  test "can Broom get server state", ctx do
    state = server_state(ctx)

    fail = pretty("result should be %Broom.State{}", state)
    assert %Broom.State{} = state, fail

    dump_state(ctx)
  end

  describe "Broom.track/2" do
    setup [:create_device, :create_alias, :create_cmd, :track_cmd, :wait_for_notification]

    @tag alias_name: "Track with Release Ack"
    @tag pio: 1
    @tag dump_tracked_refs: false
    @tag cmd_disposition: :ack
    @tag track_opts: [notify_when_released: true, track_timeout_ms: 2]
    test "can track a schema, invoke track_timeout, notify and ack", ctx do
      te = ctx.tracker_entry
      fail = pretty("TrackerEntry validation failed", te)

      # systematically confirm all %TrackerEntry fields are properly set
      assert te.acked, fail
      assert %DateTime{} = te.acked_at, fail
      assert is_integer(te.alias_id), fail
      assert te.alias_id > 0, fail
      assert te.cmd == "ack", fail
      assert te.module == Broom.Execute, fail
      assert is_pid(te.notify_pid), fail
      assert Process.alive?(te.notify_pid), fail
      assert te.track_timeout_ms == 2, fail
      assert te.orphaned == false, fail
      # NOTE: data type of refid may change in the future, only check for nil
      refute is_nil(te.refid), fail
      assert te.released, fail
      assert %DateTime{} = te.released_at, fail
      assert te.schema == Broom.DB.Command, fail
      assert is_number(te.schema_id), fail
      assert te.schema_id > 0, fail
      assert %DateTime{} = te.sent_at, fail
      assert is_nil(te.timer), fail
      assert %DateTime{} = te.tracked_at, fail

      # valid *_at fields describe processing sequence
      assert DateTime.compare(te.sent_at, te.tracked_at) == :lt, fail
      assert DateTime.compare(te.acked_at, te.released_at) == :lt, fail

      dump_tracked_refs(ctx)
    end

    @tag alias_name: "Track with Immediate Ack"
    @tag pio: 2
    @tag dump_tracked_refs: false
    @tag cmd_disposition: :ack
    @tag cmd_opts: [ack: :immediate]
    @tag track_opts: [notify_when_released: true, track_timeout_ms: 1]
    test "can track an immedidately acked schema, invoke track_timeout, notify and ack", ctx do
      te = ctx.tracker_entry
      fail = pretty("TrackerEntry validation failed", te)

      # systematically confirm all %TrackerEntry fields are properly set
      assert te.acked, fail
      assert %DateTime{} = te.acked_at, fail
      assert is_integer(te.alias_id), fail
      assert te.alias_id > 0, fail
      assert te.cmd == "ack", fail
      assert te.module == Broom.Execute, fail
      assert is_pid(te.notify_pid), fail
      assert Process.alive?(te.notify_pid), fail
      assert te.orphaned == false, fail
      # NOTE: data type of refid may change in the future, only check for nil
      refute is_nil(te.refid), fail
      assert te.released, fail
      assert %DateTime{} = te.released_at, fail
      assert te.schema == Broom.DB.Command, fail
      assert is_number(te.schema_id), fail
      assert te.schema_id > 0, fail
      assert %DateTime{} = te.sent_at, fail
      assert is_nil(te.timer), fail
      assert %DateTime{} = te.tracked_at, fail

      # valid *_at fields describe processing sequence
      assert DateTime.compare(te.sent_at, te.tracked_at) == :lt, fail
      assert DateTime.compare(te.acked_at, te.released_at) == :lt, fail

      dump_tracked_refs(ctx)
    end

    @tag alias_name: "Track with Orphan Ack"
    @tag pio: 3
    @tag dump_tracked_refs: false
    @tag cmd_disposition: :orphan
    @tag track_opts: [notify_when_released: true, track_timeout_ms: 0]
    test "can track a schema, invoke track_timeout and orphan", ctx do
      te = ctx.tracker_entry
      fail = pretty("TrackerEntry validation failed", te)

      # systematically confirm all %TrackerEntry fields are properly set
      # NOTE: orphaned cmds include acked and acked_at
      assert te.acked == true, fail
      assert %DateTime{} = te.acked_at, fail
      assert is_integer(te.alias_id), fail
      assert te.alias_id > 0, fail
      assert te.cmd == "orphan", fail
      assert te.module == Broom.Execute, fail
      assert is_pid(te.notify_pid), fail
      assert Process.alive?(te.notify_pid), fail
      assert te.orphaned == true, fail
      # NOTE: data type of refid may change in the future, only check for nil
      refute is_nil(te.refid), fail
      assert te.released, fail
      assert %DateTime{} = te.released_at, fail
      assert te.schema == Broom.DB.Command, fail
      assert is_number(te.schema_id), fail
      assert te.schema_id > 0, fail
      assert %DateTime{} = te.sent_at, fail
      assert is_nil(te.timer), fail
      assert %DateTime{} = te.tracked_at, fail

      # valid *_at fields describe processing sequence
      assert DateTime.compare(te.sent_at, te.tracked_at) == :lt, fail
      assert DateTime.compare(te.acked_at, te.released_at) == :lt, fail

      dump_tracked_refs(ctx)
    end

    @tag alias_name: "Track with Release"
    @tag pio: 4
    @tag dump_tracked_refs: false
    @tag cmd_disposition: :ack
    test "can support refid access and release via db result", ctx do
      found_te = GenServer.call(ctx.impl_mod, {:get_refid_entry, ctx.tracker_entry.refid})
      fail = pretty("should find TrackerEntry:", found_te)
      assert %Broom.TrackerEntry{} = found_te, fail

      fail = pretty("found TrackerEntry validation failed", found_te)

      # systematically confirm all %TrackerEntry fields are properly set
      # NOTE: this should be an unreleased entry
      assert found_te.acked == false, fail
      assert is_nil(found_te.acked_at), fail
      assert is_number(found_te.alias_id), fail
      assert found_te.alias_id > 0, fail
      assert found_te.cmd == "ack", fail
      assert found_te.module == Broom.Execute, fail
      assert is_nil(found_te.notify_pid), fail
      assert found_te.orphaned == false, fail
      # NOTE: data type of refid may change in the future, only check for nil
      refute is_nil(found_te.refid), fail
      assert found_te.released == false, fail
      assert is_nil(found_te.released_at), fail
      assert found_te.schema == Broom.DB.Command, fail
      assert is_number(found_te.schema_id), fail
      assert found_te.schema_id > 0, fail
      assert %DateTime{} = found_te.sent_at, fail
      assert is_reference(found_te.timer), fail
      assert %DateTime{} = found_te.tracked_at, fail

      # valid *_at fields describe processing sequence
      assert DateTime.compare(found_te.sent_at, found_te.tracked_at) == :lt, fail

      released_te = Broom.Execute.simulate_release_via_refid(found_te.refid)

      assert %Broom.TrackerEntry{} = released_te, fail

      fail = pretty("released TrackerEntry validation failed", released_te)

      # systematically confirm all %TrackerEntry fields are properly set
      # NOTE: this should be a released entry
      assert released_te.acked == true, fail
      assert %DateTime{} = released_te.acked_at, fail
      assert is_number(released_te.alias_id), fail
      assert released_te.alias_id > 0, fail
      assert released_te.cmd == "ack", fail
      assert released_te.module == Broom.Execute, fail
      assert is_nil(released_te.notify_pid), fail
      assert released_te.orphaned == false, fail
      # NOTE: data type of refid may change in the future, only check for nil
      refute is_nil(released_te.refid), fail
      assert released_te.released == true, fail
      assert %DateTime{} = released_te.released_at, fail
      assert released_te.schema == Broom.DB.Command, fail
      assert is_number(released_te.schema_id), fail
      assert released_te.schema_id > 0, fail
      assert %DateTime{} = released_te.sent_at, fail
      assert is_nil(released_te.timer), fail
      assert %DateTime{} = released_te.tracked_at, fail

      # valid *_at fields describe processing sequence
      assert DateTime.compare(released_te.sent_at, released_te.tracked_at) == :lt, fail
      assert DateTime.compare(released_te.acked_at, released_te.released_at) == :lt, fail

      dump_tracked_refs(ctx)
    end

    @tag alias_name: "Change Metrics"
    @tag pio: 5
    @tag dump_tracked_refs: false
    @tag dump_state: false
    @tag cmd_disposition: :orphan
    @tag track_opts: [notify_when_released: true, track_timeout_ms: 0]
    test "can Broom change the metrics reporting interval", ctx do
      res = Broom.via_mod_change_metrics_interval(ctx.impl_mod, "PT0.01S")

      fail = "change_metrics_interval should return {:ok, new_interval}: #{inspect(res)}"
      assert {:ok, %Broom.MetricsOpts{interval: "PT0.01S"}} == res, fail

      Process.sleep(300)

      alias Broom.{Metrics, State}
      %State{metrics: %Metrics{} = metrics} = :sys.get_state(ctx.impl_mod)

      fail = pretty("interval_ms should be 10", metrics)
      assert metrics.interval_ms == 10, fail

      dump_state(ctx) |> dump_tracked_refs()
    end
  end

  # NOTE: ctx should include ack: true or orphan: true to set disposition of cmd
  defp create_cmd(ctx) do
    alias Broom.DB.{Alias, Command}

    cmd_opts = ctx[:cmd_opts] || []

    cmd_rc = Command.add(ctx.alias_struct, %{cmd: make_cmd_binary(ctx)}, cmd_opts)

    should_be_ok_tuple(cmd_rc)
    %{ctx | cmd_struct: elem(cmd_rc, 1)}
  end

  defp create_alias(ctx) do
    alias Broom.DB.Alias

    alias_name = ctx[:alias_name] || "Broom Default Alias"
    pio = ctx[:alias_pio] || 0
    desc = ctx[:alias_description] || ctx[:describe] || "Default"
    ttl_ms = ctx[:alias_ttl_ms] || 3000

    alias_rc = Alias.create(device(ctx), alias_name, pio, description: desc, ttl_ms: ttl_ms)
    should_be_ok_tuple(alias_rc)

    alias_struct = elem(alias_rc, 1)
    should_be_struct(alias_struct, Alias)

    %{ctx | alias_struct: alias_struct, alias_name: alias_struct.name}
  end

  defp create_device(ctx) do
    alias Broom.DB.Device

    name = ctx[:dev_name] || "broom/default-device"
    h = ctx[:dev_host] || "broom-host"
    pios = ctx[:dev_pios] || 8
    now = ctx[:dev_last_seen_at] || DateTime.utc_now()
    us = ctx[:dev_latency_us] || :rand.uniform(10_000) + 10_000

    p = %{device: name, host: h, pio_count: pios, last_seen_at: now, dev_latency_us: us}

    device_rc = Device.upsert(p)
    should_be_ok_tuple(device_rc)

    device_struct = elem(device_rc, 1)
    should_be_struct(device_struct, Device)

    %{ctx | device_struct: device_struct}
  end

  defp device(ctx), do: ctx.device_struct
  # defp device_name(ctx), do: ctx.device_struct.device

  defp dump_state(ctx) do
    if ctx[:dump_state] do
      state = :sys.get_state(ctx.impl_mod)
      ["\n", inspect(state, pretty: true), "\n"] |> IO.puts()
    end

    ctx
  end

  defp dump_tracked_refs(ctx) do
    if ctx[:dump_tracked_refs] do
      state = :sys.get_state(ctx.impl_mod)
      ["\n", inspect(state.tracker.refs, pretty: true), "\n"] |> IO.puts()
    end

    ctx
  end

  defp track_cmd(ctx) do
    track_opts = ctx[:track_opts] || []

    te_rc = Broom.Execute.track(ctx.cmd_struct, track_opts)

    should_be_ok_tuple(te_rc)

    %{ctx | tracker_entry: elem(te_rc, 1)}
  end

  defp make_cmd_binary(ctx) do
    (ctx[:cmd_disposition] || :ack) |> to_string()
  end

  defp server_state(ctx), do: :sys.get_state(ctx.impl_mod)

  defp wait_for_notification(ctx) do
    track_opts = ctx[:track_opts] || []

    if track_opts[:notify_when_released] == true do
      receive do
        msg ->
          fail = pretty("notification msg did not match", msg)
          assert {Broom, :release, %Broom.TrackerEntry{}} = msg, fail

          # return the TrackerEntry
          %{ctx | tracker_entry: elem(msg, 2)}
      after
        1000 ->
          fail = pretty("should have received: {Broom, :release, %Broom.TrackerEntry{}}", :timeout)

          assert :timeout == true, fail
      end
    else
      ctx
    end
  end
end
