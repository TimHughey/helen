defmodule BroomTest do
  use ExUnit.Case
  use BroomTestShould

  @moduletag [broom: true, impl_mod: BroomTester.Commands, server_rc: {:never, nil}]

  setup_all ctx do
    ctx
  end

  setup :setup_start_server

  test "can Broom create a child_spec for the using module", ctx do
    spec = ctx.impl_mod.child_spec(initial: :test)
    should_be_non_empty_map(spec)
    should_contain(spec, id: ctx.impl_mod)
  end

  @tag start_server: true
  test "can Broom start a unique server for a using module", ctx do
    should_be_ok_tuple(ctx.server_rc)
  end

  @tag start_server: true
  test "can Broom get counts", ctx do
    should_be_ok_tuple(ctx.server_rc)

    res = ctx.impl_mod.counts()
    fail = pretty("should be == %Counts{}", res)
    assert %Broom.Counts{} == res, fail
  end

  @tag skip: false
  @tag start_server: true
  @tag pretty_puts_result: false
  test "can BroomTester get server state", ctx do
    state = server_state(ctx)

    fail = pretty("result should be %Broom.State{}", state)
    assert %Broom.State{} = state, fail

    if ctx.pretty_puts_result, do: pretty_puts_passthrough(state)
  end

  @tag start_server: true
  @tag pretty_puts_result: false
  test "can BroomTester track a Command schema already acked", ctx do
    track_opts = [notify_when_released: true]
    res = make_cmd_schema(acked: true) |> BroomTester.Commands.track(track_opts)

    receive do
      x ->
        fail = pretty("should have received: {Broom, :release, %Broom.TrackerEntry{}}", x)
        assert {Broom, :release, %Broom.TrackerEntry{}} = x, fail
    after
      1000 ->
        fail = pretty("should have received: {Broom, :release, %Broom.TrackerEntry{}}", :timeout)
        assert :timeout == true, fail
    end

    if ctx.pretty_puts_result, do: pretty_puts_passthrough(res)
  end

  @tag start_server: true
  @tag pretty_puts_result: false
  test "can BroomTester track a Command schema recently inserted", ctx do
    res = make_cmd_schema([]) |> BroomTester.Commands.track([])

    if ctx.pretty_puts_result, do: pretty_puts_passthrough(res)
  end

  @tag start_server: true
  @tag pretty_puts_result: false
  test "can BroomTester track a Command schema recently inserted and notify when released", ctx do
    track_opts = [notify_when_released: true, orphan_after_ms: 10]
    res = make_cmd_schema([]) |> BroomTester.Commands.track(track_opts)

    should_be_ok_tuple(res)

    {:ok, entry} = res
    should_be_struct(entry, Broom.TrackerEntry)

    want_ms = track_opts[:orphan_after_ms]
    fail = pretty("orphan_after_ms should == #{inspect(want_ms)}", entry)
    assert want_ms == entry.orphan_after_ms, fail

    fail = pretty("released should be false", entry)
    refute entry.released, fail

    fail = pretty("released_at should be nil", entry)
    assert is_nil(entry.released_at), fail

    fail = pretty("timer should be a reference", entry)
    assert is_reference(entry.timer), fail

    fail = pretty("notify_pid should be #{inspect(self())}", entry)
    assert self() == entry.notify_pid, fail

    Process.sleep(20)

    receive do
      x ->
        fail = pretty("should have received: {Broom, :release, %Broom.TrackerEntry{}}", x)
        assert {Broom, :release, %Broom.TrackerEntry{}} = x, fail
    after
      1000 ->
        fail = pretty("should have received: {Broom, :release, %Broom.TrackerEntry{}}", :timeout)
        assert :timeout == true, fail
    end

    if ctx.pretty_puts_result, do: pretty_puts_passthrough(res)
    #
    # server_state(ctx) |> pretty_puts()
  end

  @tag start_server: true
  test "can BroomTester change the metrics reporting interval", _ctx do
    res = BroomTester.Commands.change_metrics_interval("PT0.01S")

    fail = "change_metrics_interval should return {:ok, new_interval}: #{inspect(res)}"
    assert {:ok, "PT0.01S"} == res, fail

    track_opts = [orphan_after_ms: 3]
    res = make_cmd_schema([], :orphan) |> BroomTester.Commands.track(track_opts)
    should_be_ok_tuple(res)

    Process.sleep(5)

    track_opts = [orphan_after_ms: 3]
    res = make_cmd_schema([], :ack) |> BroomTester.Commands.track(track_opts)
    should_be_ok_tuple(res)

    Process.sleep(300)
  end

  test "the truth will set you free" do
    assert true == true
  end

  defp make_cmd_schema(collectable, kind \\ :ack) when kind in [:ack, :orphan] do
    alias BroomTester.DB.Command, as: Cmd

    defaults = [
      id: random_cmd_id(kind),
      refid: Ecto.UUID.generate(),
      alias_id: :rand.uniform(200_000),
      cmd: "on",
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      sent_at: DateTime.utc_now(),
      ack_at: if(collectable[:acked], do: DateTime.utc_now(), else: nil)
    ]

    fields = Keyword.merge(defaults, collectable)

    {:ok, struct(Cmd, fields)}
  end

  defp random_cmd_id(kind) do
    case kind do
      :ack -> :rand.uniform(50_000)
      :orphan -> :rand.uniform(50_000) + 50_000
    end
  end

  defp server_state(ctx), do: :sys.get_state(ctx.impl_mod)

  defp setup_start_server(ctx) do
    case ctx do
      %{start_server: true} -> %{ctx | server_rc: start_supervised(ctx.impl_mod)}
      _x -> ctx
    end
  end
end
