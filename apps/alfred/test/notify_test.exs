defmodule Alfred.NotifyTest do
  # can not use async due to message send/receive
  use ExUnit.Case
  use Should

  @moduletag alfred_test: true, alfred_notify: true

  alias Alfred.KnownName
  alias Alfred.Notify
  alias Alfred.Notify.{Entry, Memo, Ticket}
  alias Alfred.Test.Support

  setup [:create_known_name]
  setup [:register_name]

  test "Alfred.Notify.register/1 registers and unregisters a name" do
    name = Support.unique(:name)

    res = Notify.register(name: name)
    should_be_ok_tuple_with_struct(res, Ticket)

    {:ok, %Ticket{} = ticket} = res

    should_be_equal(ticket.name, name)

    registrations = Notify.registrations(name: name)
    fail = "#{name} should be registered for notifications"
    assert Enum.any?(registrations, fn nt -> nt.name == name end), fail

    res = Notify.unregister(ticket.ref)
    should_be_equal(res, :ok)

    registrations = Notify.registrations(name: name)

    fail = "#{name} should not be registered for notifications"
    refute Enum.any?(registrations, fn nt -> nt.name == name end), fail
  end

  @tag create_known_name: true
  @tag register_name: true
  test "Alfred.Notify registers a name and notifies", %{name: name, ticket: ticket} do
    just_saw_opts = [name: name, seen_at: DateTime.utc_now(), ttl_ms: 15_000]
    res = Notify.just_saw(just_saw_opts)

    should_be_simple_ok(res)

    registrations = Notify.registrations(all: true)
    reg = Enum.find(registrations, fn reg_nt -> reg_nt.ref == ticket.ref end)
    should_be_struct(reg, Entry)
    should_be_equal(reg.ttl_ms, just_saw_opts[:ttl_ms])

    receive do
      res ->
        should_be_tuple_with_size(res, 2)
        {mod, memo} = res
        should_be_equal(mod, Alfred)
        should_be_struct(memo, Memo)
        should_be_equal(memo.missing?, false)
        should_be_equal(memo.name, name)
        should_be_equal(memo.pid, self())
        should_be_equal(memo.ref, ticket.ref)
        should_be_equal(memo.seen_at, just_saw_opts[:seen_at])
    after
      1000 -> refute true, "receive timeout"
    end
  end

  @tag create_known_name: true
  @tag register_name: true
  @tag frequency: [interval_ms: 1000]
  test "Alfred.Notify honors notify interval", %{name: name, ticket: ticket} do
    just_saw_opts = [name: name, seen_at: DateTime.utc_now(), ttl_ms: 15_000]
    res = Notify.just_saw(just_saw_opts)

    assert res == :ok

    registrations = Notify.registrations(all: true)
    reg = Enum.find(registrations, fn reg_nt -> reg_nt.ref == ticket.ref end)
    should_be_struct(reg, Entry)
    should_be_equal(reg.ttl_ms, just_saw_opts[:ttl_ms])

    receive do
      res ->
        should_be_tuple_with_size(res, 2)
        {mod, memo} = res
        should_be_equal(mod, Alfred)
        should_be_struct(memo, Memo)
        should_be_equal(memo.missing?, false)
        should_be_equal(memo.name, name)
        should_be_equal(memo.pid, self())
        should_be_equal(memo.ref, ticket.ref)
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

  describe "Alfred.Notify.Server.handle_info/2 handles" do
    @tag create_known_name: true
    @tag register_name: true
    @tag frequency: [interval_ms: 0]
    @tag missing_ms: 10
    test "missing messages", %{name: name, ticket: ticket} do
      receive do
        msg ->
          should_be_msg_tuple_with_mod_and_struct(msg, Alfred, Memo)
          {_mod, memo} = msg
          should_be_equal(memo.name, name)
          should_be_equal(memo.missing?, true)
          should_be_equal(memo.ref, ticket.ref)
      after
        1000 -> refute true, "{Alfred, Memo} missing msg never received"
      end
    end

    @tag create_known_name: true
    @tag register_name: true
    @tag frequency: [interval_ms: 0]
    test "down messages", %{ticket: ticket} do
      alias Alfred.Notify.Registration.Key

      genserver_pid = GenServer.whereis(Alfred.Notify.Server)
      should_be_pid(genserver_pid)

      res = Process.send(genserver_pid, {:DOWN, ticket.ref, :process, self(), :test}, [])
      should_be_simple_ok(res)

      registrations = Notify.registrations()

      %Ticket{ref: down_ref} = ticket

      for {%Key{ref: ^down_ref}, _} <- registrations do
        refute true, "#{inspect(down_ref)} should not be registered"
      end
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

    ticket = should_be_ok_tuple(res)

    Map.put(ctx, :ticket, ticket)
  end

  def register_name(ctx), do: ctx
end
