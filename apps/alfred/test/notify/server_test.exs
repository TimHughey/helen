defmodule Alfred.NotifyServerTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag alfred: true, alfred_notify_server: true

  alias Alfred.Notify.{Memo, Server, State, Ticket}
  alias Alfred.SeenName
  alias Alfred.NamesAid

  setup_all do
    call_opts = [notify_server: __MODULE__]

    ok_pid = start_supervised({Server, call_opts})

    pid = should_be_ok_tuple_with_pid(ok_pid)

    {:ok, %{pid: pid, server_name: __MODULE__, call_opts: call_opts, state: %State{}}}
  end

  setup [:register_name, :make_seen_list]

  describe "Alfred.Notify.Server starts" do
    test "via applicaton" do
      pid = GenServer.whereis(Server)

      should_be_pid(pid)
    end

    test "with specified name", %{server_name: server_name} do
      res = GenServer.whereis(server_name)

      should_be_pid(res)
    end
  end

  describe "Alfred.Notify.Server.call/2" do
    test "handles when a server is not available" do
      res = Server.call({:foo}, notify_server: Foo.Bar)

      should_be_match(res, {:no_server, Foo.Bar})
    end

    test "handles when the server is available", ctx do
      regs = Server.call(:registrations, ctx.call_opts)

      should_be_map(regs)
    end
  end

  describe "Alfred.Notify.Server.cast/2" do
    test "honors :notify_server opt", ctx do
      res = Server.cast({:notify, []}, ctx.call_opts)

      should_be_simple_ok(res)
    end
  end

  describe "Alfred.Notify.Server.handle_call/3" do
    @tag register_name: []
    test "handles {:register, opts} messages", %{ticket: ticket} do
      should_be_struct(ticket, Ticket)
    end

    @tag register_name: []
    @tag seen_list: [include_ticket: [ttl_ms: 15_000], count: 100]
    test "handles {:notify, seen_list}", ctx do
      result = Server.call({:notify, ctx.seen_list}, ctx.call_opts)
      should_be_match(result, [ctx.ticket.name])

      receive do
        {Alfred, memo} ->
          should_be_struct(memo, Memo)
          should_be_equal(memo.name, ctx.ticket.name)
      after
        100 -> refute true, "should have received memo"
      end
    end

    @tag register_name: []
    test "handles {:unregister, opts} messages", %{ticket: ticket, call_opts: call_opts} do
      res = Server.call({:unregister, ticket.ref}, call_opts)
      should_be_simple_ok(res)
    end
  end

  describe "Alfred.Notify.Server.handle_cast/2" do
    @tag register_name: []
    @tag seen_list: [include_ticket: [ttl_ms: 15_000], count: 100]
    test "handles {:notify, seen_list}", ctx do
      res = Server.cast({:notify, ctx.seen_list}, ctx.call_opts)
      should_be_simple_ok(res)

      receive do
        {Alfred, memo} ->
          should_be_struct(memo, Memo)
          should_be_equal(memo.name, ctx.ticket.name)
      after
        100 -> refute true, "should have received memo"
      end
    end
  end

  describe "Alfred.Notify.Server.handle_info/2" do
    @tag register_name: []
    test ":DOWN message removes registrations for pid", %{pid: pid, call_opts: call_opts} do
      regs_before = Server.call(:registrations, call_opts) |> map_size()

      Process.send(pid, {:DOWN, make_ref(), :process, self(), :reason}, [])

      regs_after = Server.call(:registrations, call_opts) |> map_size()

      assert regs_after < regs_before, msg(regs_before, "should be less than", regs_after)
    end

    @tag register_name: [missing_ms: 10]
    test ":missing message sends a missing memo", ctx do
      receive do
        {Alfred, memo} ->
          should_be_struct(memo, Memo)
          should_be_equal(memo.name, ctx.ticket.name)
          should_be_equal(memo.missing?, true)
      after
        100 -> refute true, "should have received missing memo"
      end
    end
  end

  defp make_seen_list(%{seen_list: seen_opts} = ctx) do
    include_ticket_opts = seen_opts[:include_ticket]

    seen_list =
      if include_ticket_opts != [] do
        ticket_to_seen_name(ctx.ticket, include_ticket_opts) |> List.wrap()
      else
        []
      end

    count = seen_opts[:count] || 0

    %{seen_list: seen_list |> make_multiple_seen_names(count)}
  end

  defp make_seen_list(_), do: :ok

  defp make_multiple_seen_names(seen_list, 0), do: seen_list

  defp make_multiple_seen_names(seen_list, count) do
    for _ <- 1..count, reduce: seen_list do
      acc ->
        utc_now = DateTime.utc_now()
        seen_name = %SeenName{name: NamesAid.unique("notifyserver"), ttl_ms: 15_000, seen_at: utc_now}
        [acc, seen_name]
    end
    |> List.flatten()
  end

  defp register_name(%{register_name: opts, call_opts: call_opts}) when is_list(opts) do
    # NOTE: ttl_ms is generally not provided when registering

    name = opts[:name] || NamesAid.unique("notifyserver")
    frequency = opts[:frequency] || []
    missing_ms = opts[:missing_ms] || 60_000
    pid = opts[:pid] || self()
    register_opts = [name: name, frequency: frequency, missing_ms: missing_ms, pid: pid]

    result = Server.call({:register, register_opts}, call_opts)

    ticket = should_be_ok_tuple(result)

    should_be_struct(ticket, Ticket)
    should_be_equal(ticket.name, name)
    should_be_equal(ticket.opts.missing_ms, missing_ms)
    should_be_reference(ticket.ref)

    %{ticket: ticket, registered_opts: register_opts}
  end

  defp register_name(_), do: :ok

  defp ticket_to_seen_name(%Ticket{} = ticket, opts) do
    ttl_ms = opts[:ttl_ms] || 1000
    seen_at = opts[:seen_at] || DateTime.utc_now()

    %SeenName{name: ticket.name, ttl_ms: ttl_ms, seen_at: seen_at}
  end
end
