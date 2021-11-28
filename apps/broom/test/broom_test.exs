defmodule BroomTest do
  use ExUnit.Case
  use Should

  alias Broom.Repo, as: Repo
  alias Broom.Test.Support

  # setup common ctx keys for map matching / updates
  @moduletag [
    broom: true,
    impl_mod: Broom.Execute,
    host: nil,
    device: nil,
    dev_alias: nil,
    alias_name: nil,
    added_cmd: nil,
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
    Should.Be.NonEmpty.map(spec)
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
    setup [:create_wrapped, :track_cmd, :wait_for_notification]

    @tag dev_alias_opts: [name: "Track with Release Ack", pio: 1]
    @tag dump_tracked_refs: false
    @tag cmd_disposition: :ack
    @tag track_opts: [notify_when_released: true, track_timeout_ms: 2]
    test "can track a schema, invoke track_timeout, notify and ack", ctx do
      te = ctx.tracker_entry
      fail = pretty("TrackerEntry validation failed", te)

      # systematically confirm all %TrackerEntry fields are properly set
      assert te.acked, fail
      assert %DateTime{} = te.acked_at, fail
      assert is_integer(te.dev_alias_id), fail
      assert te.dev_alias_id > 0, fail
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
      assert te.schema == Broom.Command, fail
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

    @tag dev_alias_opts: [name: "Track with Immediate Ack", pio: 2]
    @tag dump_tracked_refs: false
    @tag cmd_disposition: :ack
    @tag cmd_opts: [ack: :immediate]
    @tag track_opts: [notify_when_released: true, track_timeout_ms: 1]
    test "can track an immediately acked schema, invoke track_timeout, notify and ack", ctx do
      te = ctx.tracker_entry
      fail = pretty("TrackerEntry validation failed", te)

      # systematically confirm all %TrackerEntry fields are properly set
      assert te.acked, fail
      assert %DateTime{} = te.acked_at, fail
      assert is_integer(te.dev_alias_id), fail
      assert te.dev_alias_id > 0, fail
      assert te.cmd == "ack", fail
      assert te.module == Broom.Execute, fail
      assert is_pid(te.notify_pid), fail
      assert Process.alive?(te.notify_pid), fail
      assert te.orphaned == false, fail
      # NOTE: data type of refid may change in the future, only check for nil
      refute is_nil(te.refid), fail
      assert te.released, fail
      assert %DateTime{} = te.released_at, fail
      assert te.schema == Broom.Command, fail
      assert is_number(te.schema_id), fail
      assert te.schema_id > 0, fail
      assert %DateTime{} = te.sent_at, fail
      assert is_nil(te.timer), fail
      assert %DateTime{} = te.tracked_at, fail

      # valid *_at fields describe processing sequence
      assert DateTime.compare(te.sent_at, te.tracked_at) == :lt, fail
      assert DateTime.compare(te.acked_at, te.released_at) == :lt, fail

      # check the actual Command
      cmd_schema = Repo.get!(Broom.Command, te.schema_id)
      fail = pretty("Command validation failed", cmd_schema)
      assert cmd_schema.acked == true, fail
      refute cmd_schema.orphaned, fail
      # this is an immediate ack so sent_at == acked_at and rt_latency_us == 0
      assert cmd_schema.rt_latency_us == 0, fail
      assert DateTime.compare(cmd_schema.sent_at, cmd_schema.acked_at) == :eq, fail
      assert DateTime.compare(cmd_schema.acked_at, te.released_at) == :lt, fail

      dump_tracked_refs(ctx)
    end

    @tag dev_alias_opts: [name: "Track with Orphan Ack", pio: 3]
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
      assert is_integer(te.dev_alias_id), fail
      assert te.dev_alias_id > 0, fail
      assert te.cmd == "orphan", fail
      assert te.module == Broom.Execute, fail
      assert is_pid(te.notify_pid), fail
      assert Process.alive?(te.notify_pid), fail
      assert te.orphaned == true, fail
      # NOTE: data type of refid may change in the future, only check for nil
      refute is_nil(te.refid), fail
      assert te.released, fail
      assert %DateTime{} = te.released_at, fail
      assert te.schema == Broom.Command, fail
      assert is_number(te.schema_id), fail
      assert te.schema_id > 0, fail
      assert %DateTime{} = te.sent_at, fail
      assert is_nil(te.timer), fail
      assert %DateTime{} = te.tracked_at, fail

      # valid *_at fields describe processing sequence
      assert DateTime.compare(te.sent_at, te.tracked_at) == :lt, fail
      assert DateTime.compare(te.acked_at, te.released_at) == :lt, fail

      # check the actual Command
      cmd_schema = Repo.get!(Broom.Command, te.schema_id)
      fail = pretty("Command validation failed", cmd_schema)
      assert cmd_schema.acked == true, fail
      assert cmd_schema.orphaned, fail
      assert cmd_schema.rt_latency_us > 0, fail
      assert DateTime.compare(cmd_schema.sent_at, cmd_schema.acked_at) == :lt, fail
      assert DateTime.compare(cmd_schema.acked_at, te.released_at) == :lt, fail

      dump_tracked_refs(ctx)
    end

    @tag dev_alias_opts: [name: "Track with Release", pio: 3]
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
      assert is_number(found_te.dev_alias_id), fail
      assert found_te.dev_alias_id > 0, fail
      assert found_te.cmd == "ack", fail
      assert found_te.module == Broom.Execute, fail
      assert is_nil(found_te.notify_pid), fail
      assert found_te.orphaned == false, fail
      # NOTE: data type of refid may change in the future, only check for nil
      refute is_nil(found_te.refid), fail
      assert found_te.released == false, fail
      assert is_nil(found_te.released_at), fail
      assert found_te.schema == Broom.Command, fail
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
      assert is_number(released_te.dev_alias_id), fail
      assert released_te.dev_alias_id > 0, fail
      assert released_te.cmd == "ack", fail
      assert released_te.module == Broom.Execute, fail
      assert is_nil(released_te.notify_pid), fail
      assert released_te.orphaned == false, fail
      # NOTE: data type of refid may change in the future, only check for nil
      refute is_nil(released_te.refid), fail
      assert released_te.released == true, fail
      assert %DateTime{} = released_te.released_at, fail
      assert released_te.schema == Broom.Command, fail
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

    @tag dev_alias_opts: [name: "Change Metrics", pio: 5]
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
    cmd_opts = ctx[:cmd_opts] || []

    added_cmd = Broom.Command.add(ctx.dev_alias, make_cmd_binary(ctx), cmd_opts)

    should_be_schema(added_cmd, Broom.Command)

    %{ctx | added_cmd: added_cmd}
  end

  defp create_alias(ctx) when is_map_key(ctx, :dev_alias_opts) do
    default_opts = [decription: "default", ttl_ms: 3000]
    dev_alias_opts = Keyword.merge(ctx.dev_alias_opts, default_opts)

    dev_alias = Support.add_dev_alias(ctx.device, dev_alias_opts)

    should_be_struct(dev_alias, Broom.DevAlias)

    %{ctx | dev_alias: dev_alias, alias_name: dev_alias.name}
  end

  defp create_alias(ctx), do: ctx

  defp create_device(ctx) do
    ident = ctx[:dev_ident] || "broom/default-device"
    # h = ctx[:dev_host] || "broom-host"
    pios = ctx[:dev_pios] || 8
    # now = ctx[:dev_last_seen_at] || DateTime.utc_now()
    device_opts = [ident: ident, family: "i2c", mutable: true, pios: pios]

    device = Support.add_device(ctx.host, device_opts)
    should_be_schema(device, Broom.Device)

    %{ctx | device: device}
  end

  defp create_host(ctx) do
    host_opts = [host: "broom.testhost", name: "Broom Test Host"]
    host = Support.add_host(host_opts)
    should_be_schema(host, Broom.Host)

    %{ctx | host: host}
  end

  defp create_wrapped(ctx) do
    Repo.transaction(fn ->
      ctx |> create_host() |> create_device() |> create_alias() |> create_cmd()
    end)
    |> elem(1)
  end

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

    te_rc = Broom.Execute.track(ctx.added_cmd, track_opts)

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
          assert {Broom, %Broom.TrackerEntry{}} = msg, fail

          # return the TrackerEntry
          %{ctx | tracker_entry: elem(msg, 1)}
      after
        1000 ->
          fail = pretty("should have received: {Broom, %Broom.TrackerEntry{}}", :timeout)

          assert :timeout == true, fail
      end
    else
      ctx
    end
  end
end
