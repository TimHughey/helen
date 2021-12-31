defmodule BroomTest do
  use ExUnit.Case

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

  setup ctx do
    ctx
  end

  # defmacro assert_tracker_entry(te, want_kv) do
  #   quote location: :keep, bind_quoted: [te: te, want_kv: want_kv] do
  #
  #     want_dt = [:acked_at, :released_at, :sent_at, :tracked_at]
  #     want_types = [dev_alias_id: :integer, ]
  #     want_true = [:acked, :released]
  #
  #
  #     # systematically confirm all %TrackerEntry fields are properly set
  #     assert te.acked, fail
  #     assert %DateTime{} = te.acked_at, fail
  #     assert is_integer(te.dev_alias_id), fail
  #     assert te.dev_alias_id > 0, fail
  #     assert te.cmd == "ack", fail
  #     assert te.module == Broom.Execute, fail
  #     assert is_pid(te.notify_pid), fail
  #     assert Process.alive?(te.notify_pid), fail
  #     assert te.track_timeout_ms == 2, fail
  #     assert te.orphaned == false, fail
  #     # NOTE: data type of refid may change in the future, only check for nil
  #     refute is_nil(te.refid), fail
  #     assert te.released, fail
  #     assert %DateTime{} = te.released_at, fail
  #     assert te.schema == Broom.Command, fail
  #     assert is_number(te.schema_id), fail
  #     assert te.schema_id > 0, fail
  #     assert %DateTime{} = te.sent_at, fail
  #     assert is_nil(te.timer), fail
  #     assert %DateTime{} = te.tracked_at, fail
  #
  #     # valid *_at fields describe processing sequence
  #     assert DateTime.compare(te.sent_at, te.tracked_at) == :lt, fail
  #     assert DateTime.compare(te.acked_at, te.released_at) == :lt, fail
  #
  #   end
  # end

  test "can Broom create a child_spec for the using module", %{impl_mod: impl_mod} do
    assert %{id: ^impl_mod} = impl_mod.child_spec(initial: :test)
  end

  test "can Broom get counts", ctx do
    assert %Broom.Counts{} = Broom.via_mod_counts(ctx.impl_mod)
  end

  test "can Broom reset counts", ctx do
    assert {:reset, %Broom.Counts{}} =
             Broom.via_mod_counts_reset(ctx.impl_mod, [:orphaned, :tracked, :not_a_count])
  end

  @tag skip: false
  @tag dump_state: false
  test "can Broom get server state", ctx do
    assert %Broom.State{tracker: %{}} = server_state(ctx)

    dump_state(ctx)
  end

  describe "Broom.track/2" do
    setup [:create_wrapped, :track_cmd, :wait_for_notification]

    @tag dev_alias_opts: [name: "Track with Release Ack", pio: 1]
    @tag dump_tracked_refs: false
    @tag cmd_disposition: :ack
    @tag track_opts: [notify_when_released: true, track_timeout_ms: 2]
    test "can track a schema, invoke track_timeout, notify and ack", %{tracker_entry: te} do
      assert %Broom.TrackerEntry{
               acked: true,
               acked_at: %DateTime{},
               dev_alias_id: dev_alias_id,
               cmd: "ack",
               module: Broom.Execute,
               notify_pid: notify_pid,
               track_timeout_ms: 2,
               orphaned: false,
               refid: <<_::binary>>,
               released: true,
               released_at: %DateTime{},
               schema: Broom.Command,
               schema_id: schema_id,
               sent_at: %DateTime{},
               timer: nil,
               tracked_at: %DateTime{}
             } = te

      assert is_integer(dev_alias_id)
      assert dev_alias_id > 0
      assert is_pid(notify_pid)
      assert Process.alive?(notify_pid)
      assert is_number(schema_id)
      assert schema_id > 0

      # valid *_at fields describe processing sequence
      assert DateTime.compare(te.sent_at, te.tracked_at) == :lt
      assert DateTime.compare(te.acked_at, te.released_at) == :lt

      # dump_tracked_refs(ctx)
    end

    @tag dev_alias_opts: [name: "Track with Immediate Ack", pio: 2]
    @tag dump_tracked_refs: false
    @tag cmd_disposition: :ack
    @tag cmd_opts: [ack: :immediate]
    @tag track_opts: [notify_when_released: true, track_timeout_ms: 1]
    test "can track an immediately acked schema, invoke track_timeout, notify and ack", ctx do
      te = ctx.tracker_entry
      fail = "TrackerEntry validation failed"

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
      fail = "Command validation failed"
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
      fail = "TrackerEntry validation failed"

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
      fail = "Command validation failed"
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
      fail = "should find TrackerEntry:"
      assert %Broom.TrackerEntry{} = found_te, fail

      fail = "found TrackerEntry validation failed"

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

      fail = "released TrackerEntry validation failed"

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
      assert {:ok, %Broom.MetricsOpts{interval: "PT0.01S"}} =
               Broom.via_mod_change_metrics_interval(ctx.impl_mod, "PT0.01S")

      Process.sleep(300)

      assert %Broom.State{metrics: %Broom.Metrics{interval_ms: 10}} = :sys.get_state(ctx.impl_mod)

      dump_state(ctx) |> dump_tracked_refs()
    end
  end

  @dev_alias_defaults [decription: "default", ttl_ms: 3000]
  defp create_wrapped(%{dev_alias_opts: dev_alias_opts} = ctx) do
    Repo.transaction(fn ->
      host_opts = [host: "broom.testhost", name: "Broom Test Host"]
      host = Support.add_host(host_opts)
      assert %Broom.Host{ident: "broom.testhost"} = host

      ident = "broom/default-device"
      device = Support.add_device(host, ident: ident, family: "i2c", mutable: true, pios: 8)
      assert %Broom.Device{ident: ^ident} = device

      dev_alias_opts = Keyword.merge(@dev_alias_defaults, dev_alias_opts)
      dev_alias = Support.add_dev_alias(device, dev_alias_opts)
      assert %Broom.DevAlias{} = dev_alias

      # NOTE: ctx should include ack: true or orphan: true to set disposition of cmd
      cmd_opts = ctx[:cmd_opts] || []
      added_cmd = Broom.Command.add(dev_alias, make_cmd_binary(ctx), cmd_opts)

      assert %Broom.Command{} = added_cmd

      %{host: host, device: device, dev_alias: dev_alias, alias_name: dev_alias.name, added_cmd: added_cmd}
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

    assert {:ok, %Broom.TrackerEntry{} = te} = Broom.Execute.track(ctx.added_cmd, track_opts)

    %{tracker_entry: te}
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
          assert {Broom, %Broom.TrackerEntry{}} = msg

          # return the TrackerEntry to merge into ctx
          %{tracker_entry: elem(msg, 1)}
      after
        1000 ->
          assert :timeout == true, "should have received: {Broom, %Broom.TrackerEntry{}}"
          # nothing to merge into ctx
          :ok
      end
    else
      :ok
    end
  end
end
