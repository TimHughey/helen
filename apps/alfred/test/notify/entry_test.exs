defmodule Alfred.NotifyEntryTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag alfred: true, alfred_notify_entry: true

  alias Alfred.Notify.{Entry, Memo}
  alias Alfred.NamesAid

  defmacro should_receive_memo_for(entry, opts) do
    quote location: :keep, bind_quoted: [entry: entry, opts: opts] do
      expected_memo = %Memo{
        name: entry.name,
        ref: entry.ref,
        pid: entry.pid,
        seen_at: opts[:seen_at],
        missing?: opts[:missing?]
      }

      assert_received {Alfred, ^expected_memo}, msg(expected_memo, "not received")
    end
  end

  setup [:make_entry, :first_notify]

  describe "Alfred.Notify.Entry.new/1" do
    @tag make_entry: []
    test "creates Entry with minimal opts", %{entry: entry} do
      should_be_equal(entry.ttl_ms, 0)
      should_be_equal(entry.missing_ms, 60_000)
      should_be_equal(entry.interval_ms, 60_000)
    end

    @tag make_entry: [frequency: :all]
    test "creates Entry when frequency: :all is specified", %{entry: entry} do
      should_be_equal(entry.ttl_ms, 0)
      should_be_equal(entry.missing_ms, 60_000)
      should_be_equal(entry.interval_ms, 0)
    end

    @tag make_entry: [frequency: [interval_ms: 30_000]]
    test "creates Entry when frequency: ms is specified", %{entry: entry} do
      should_be_equal(entry.ttl_ms, 0)
      should_be_equal(entry.missing_ms, 60_000)
      should_be_equal(entry.interval_ms, 30_000)
    end

    @tag make_entry: [missing_ms: 10_000, ttl_ms: 15_000]
    test "uses ttl_ms when available (instead of missing_ms)", %{entry: entry} do
      should_be_equal(entry.ttl_ms, 15_000)
      should_be_equal(entry.missing_ms, 15_000)
    end
  end

  describe "Alfred.Notify.Entry.notify/2" do
    @tag make_entry: []
    test "updates ttl_ms", %{entry: entry} do
      opts = [seen_at: DateTime.utc_now(), ttl_ms: 1000]

      new_entry = Entry.notify(entry, opts)

      should_be_equal(new_entry.ttl_ms, opts[:ttl_ms])
    end

    @tag make_entry: []
    @tag first_notify: true
    test "always sends first notification", %{entry: entry} do
      epoch = DateTime.from_unix!(0)
      should_be_datetime_greater_than(entry.last_notify_at, epoch)
    end

    @tag make_entry: [frequency: [interval_ms: 1000]]
    @tag first_notify: true
    test "honors frequency", %{entry: entry} do
      # part 1: enough time has elapsed, should receive notify message
      seen_at = DateTime.utc_now() |> DateTime.add(entry.interval_ms, :millisecond)
      opts = [seen_at: seen_at, missing?: false]

      entry = Entry.notify(entry, opts)

      should_receive_memo_for(entry, opts)

      # part 2: quick notify, not enough time has elapsed, should not receive msg
      opts = [seen_at: DateTime.utc_now(), missing?: true]
      Entry.notify(entry, opts)

      refute_received {Alfred, %Memo{}}, "should not have notified"
    end
  end

  def first_notify(%{first_notify: true, entry: entry}) do
    opts = [seen_at: DateTime.utc_now(), missing?: false]
    entry = Entry.notify(entry, opts)

    should_be_struct(entry, Entry)

    should_receive_memo_for(entry, opts)

    # pass the updated Entry along in the context
    %{entry: entry}
  end

  def first_notify(ctx), do: ctx

  def make_entry(%{make_entry: args}) when is_list(args) do
    default_args = [name: NamesAid.unique("entry"), pid: self()]
    final_args = Keyword.merge(args, default_args, fn _k, v1, _v2 -> v1 end)

    entry = Entry.new(final_args)

    should_be_struct(entry, Entry)
    should_be_binary(entry.name)
    should_be_reference(entry.ref)
    should_be_reference(entry.monitor_ref)
    should_be_datetime(entry.last_notify_at)
    should_be_integer(entry.ttl_ms)
    should_be_integer(entry.interval_ms)
    should_be_integer(entry.missing_ms)
    should_be_timer_with_remaining_ms(entry.missing_timer, entry.missing_ms)

    %{entry: entry}
  end

  def make_entry(ctx), do: ctx
end
