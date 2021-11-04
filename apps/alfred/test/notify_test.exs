defmodule Alfred.NotifyTest do
  # can not use async due message send/receive
  use ExUnit.Case
  use Should

  @moduletag alfred_test: true, alfred_notify: true

  alias Alfred.KnownName
  alias Alfred.{Notify, NotifyMemo, NotifyTo}
  alias Alfred.Test.Support

  setup [:create_known_name]
  setup [:register_name]

  test "Alfred.Notify.register/1 registers and unregisters a name" do
    name = Support.unique(:name)

    res = Notify.register(name: name)
    should_be_ok_tuple_with_struct(res, NotifyTo)

    {:ok, %NotifyTo{} = nt} = res

    should_be_equal(nt.name, name)

    registrations = Notify.registrations(name: name)
    fail = "#{name} should be registered for notifications"
    assert Enum.any?(registrations, fn nt -> nt.name == name end), fail

    res = Notify.unregister(nt.ref)
    should_be_equal(res, :ok)

    registrations = Notify.registrations(name: name)

    fail = "#{name} should not be registered for notifications"
    refute Enum.any?(registrations, fn nt -> nt.name == name end), fail
  end

  @tag create_known_name: true
  @tag register_name: true
  test "Alfred.Notify registers a name and notifies", %{name: name, notify_to: nt} do
    just_saw_opts = [name: name, seen_at: DateTime.utc_now(), ttl_ms: 15_000]
    res = Notify.just_saw(just_saw_opts)

    assert res == :ok

    registrations = Notify.registrations(all: true)
    reg = Enum.find(registrations, fn reg_nt -> reg_nt.ref == nt.ref end)
    should_be_struct(reg, NotifyTo)
    should_be_equal(reg.ttl_ms, just_saw_opts[:ttl_ms])

    receive do
      res ->
        should_be_tuple_with_size(res, 2)
        {mod, memo} = res
        should_be_equal(mod, Alfred)
        should_be_struct(memo, NotifyMemo)
        should_be_equal(memo.missing?, false)
        should_be_equal(memo.name, name)
        should_be_equal(memo.pid, self())
        should_be_equal(memo.ref, nt.ref)
        should_be_equal(memo.seen_at, just_saw_opts[:seen_at])
    after
      1000 -> refute true, "receive timeout"
    end
  end

  @tag create_known_name: true
  @tag register_name: true
  @tag frequency: [interval_ms: 1000]
  test "Alfred.Notify honors notify interval", %{name: name, notify_to: nt} do
    just_saw_opts = [name: name, seen_at: DateTime.utc_now(), ttl_ms: 15_000]
    res = Notify.just_saw(just_saw_opts)

    assert res == :ok

    registrations = Notify.registrations(all: true)
    reg = Enum.find(registrations, fn reg_nt -> reg_nt.ref == nt.ref end)
    should_be_struct(reg, NotifyTo)
    should_be_equal(reg.ttl_ms, just_saw_opts[:ttl_ms])

    receive do
      res ->
        should_be_tuple_with_size(res, 2)
        {mod, memo} = res
        should_be_equal(mod, Alfred)
        should_be_struct(memo, NotifyMemo)
        should_be_equal(memo.missing?, false)
        should_be_equal(memo.name, name)
        should_be_equal(memo.pid, self())
        should_be_equal(memo.ref, nt.ref)
        should_be_equal(memo.seen_at, just_saw_opts[:seen_at])
    after
      1000 -> refute true, "receive timeout"
    end

    # second notify in quick succession
    just_saw_opts = [name: name, seen_at: DateTime.utc_now(), ttl_ms: 15_000]
    res = Notify.just_saw(just_saw_opts)

    assert res == :ok

    receive do
      msg -> refute true, "should not have received notification:\n#{inspect(msg, pretty: true)}"
    after
      100 -> assert true
    end
  end

  def create_known_name(%{create_known_name: true} = ctx) do
    name = ctx[:name] || Support.unique(:name)
    mutable? = ctx[:mutable?] || false
    ttl_ms = ctx[:ttl_ms] || 15_000

    merge = %{name: name, known_name: KnownName.new(name, mutable?, ttl_ms, __MODULE__)}

    Map.merge(merge, ctx)
  end

  def create_known_name(ctx), do: ctx

  def register_name(%{register_name: true} = ctx) do
    register_opts = Map.take(ctx, [:name, :ttl_ms, :missing_ms, :frequency]) |> Enum.into([])
    res = Notify.register(register_opts)

    should_be_ok_tuple_with_struct(res, NotifyTo)
    {:ok, nt} = res

    merge = %{notify_to: nt}
    Map.merge(merge, ctx)
  end

  def register_name(ctx), do: ctx
end
