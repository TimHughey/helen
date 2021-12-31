defmodule Alfred.NotifyEntryTest do
  use ExUnit.Case, async: true

  @moduletag alfred: true, alfred_notify_entry: true

  defmacro assert_entry(entry, kv_pairs) do
    quote bind_quoted: [entry: entry, kv_pairs: kv_pairs] do
      # merge in defaults
      want_kv = Keyword.merge([ttl_ms: 0, missing_ms: 60_000, interval_ms: 60_000], kv_pairs)
      want_entry = struct(entry, want_kv)

      assert ^entry = want_entry
    end
  end

  defmacro should_receive_memo_for(entry, opts) do
    quote bind_quoted: [entry: entry, opts: opts] do
      expected_memo = %Alfred.Notify.Memo{
        name: entry.name,
        ref: entry.ref,
        pid: entry.pid,
        seen_at: opts[:seen_at],
        missing?: opts[:missing?]
      }

      assert_received {Alfred, ^expected_memo}
    end
  end

  setup [:make_entry, :first_notify]

  describe "Alfred.Notify.Entry.new/1" do
    @tag make_entry: []
    test "creates Entry with minimal opts", ctx do
      ctx.entry
      |> assert_entry([])
    end

    @tag make_entry: [frequency: :all]
    test "creates Entry when frequency: :all is specified", ctx do
      ctx.entry
      |> assert_entry(interval_ms: 0)
    end

    @tag make_entry: [frequency: [interval_ms: 30_000]]
    test "creates Entry when frequency: ms is specified", ctx do
      ctx.entry
      |> assert_entry(interval_ms: 30_000)
    end

    @tag make_entry: [missing_ms: 10_000, ttl_ms: 15_000]
    test "uses ttl_ms when available (instead of missing_ms)", ctx do
      ctx.entry
      |> assert_entry(ttl_ms: 15_000, missing_ms: 15_000)
    end
  end

  describe "Alfred.Notify.Entry.notify/2" do
    @tag make_entry: []
    test "updates ttl_ms", ctx do
      opts = [seen_at: DateTime.utc_now(), ttl_ms: 1000]

      ctx.entry
      |> Alfred.Notify.Entry.notify(opts)
      |> assert_entry(ttl_ms: opts[:ttl_ms], missing_ms: opts[:ttl_ms])
    end

    @tag make_entry: []
    @tag first_notify: true
    test "always sends first notification", ctx do
      epoch = DateTime.from_unix!(0)

      assert %Alfred.Notify.Entry{last_notify_at: last_notify} = ctx.entry
      assert DateTime.compare(last_notify, epoch) == :gt
    end

    @tag make_entry: [frequency: [interval_ms: 1000]]
    @tag first_notify: true
    test "honors frequency", %{entry: entry} do
      # part 1: enough time has elapsed, should receive notify message
      seen_at = DateTime.utc_now() |> DateTime.add(entry.interval_ms, :millisecond)
      opts = [seen_at: seen_at, missing?: false]

      entry = Alfred.Notify.Entry.notify(entry, opts)
      should_receive_memo_for(entry, opts)

      # part 2: quick notify, not enough time has elapsed, should not receive msg
      opts = [seen_at: DateTime.utc_now(), missing?: true]
      Alfred.Notify.Entry.notify(entry, opts)

      refute_received {Alfred, %Alfred.Notify.Memo{}}, "should not have notified"
    end
  end

  def first_notify(%{first_notify: true, entry: entry}) do
    opts = [seen_at: DateTime.utc_now(), missing?: false]
    entry = Alfred.Notify.Entry.notify(entry, opts)
    assert %Alfred.Notify.Entry{} = entry

    should_receive_memo_for(entry, opts)

    # pass the updated Entry along in the context
    %{entry: entry}
  end

  def first_notify(ctx), do: ctx

  def make_entry(%{make_entry: args}) when is_list(args) do
    default_args = [name: Alfred.NamesAid.unique("entry"), pid: self()]
    final_args = Keyword.merge(args, default_args, fn _k, v1, _v2 -> v1 end)

    entry = Alfred.Notify.Entry.new(final_args)

    assert %Alfred.Notify.Entry{
             name: <<_::binary>>,
             ref: ref,
             monitor_ref: monitor_ref,
             last_notify_at: %DateTime{},
             ttl_ms: ttl_ms,
             interval_ms: interval_ms,
             missing_ms: missing_ms,
             missing_timer: missing_timer
           } = entry

    Enum.all?([ref, monitor_ref, missing_timer], fn x -> assert is_reference(x) end)
    Enum.all?([ttl_ms, interval_ms, missing_ms], fn x -> assert is_integer(x) end)

    %{entry: entry}
  end

  def make_entry(ctx), do: ctx
end
