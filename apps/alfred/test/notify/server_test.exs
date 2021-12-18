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

    pid = Should.Be.Ok.tuple_with_pid(ok_pid)

    {:ok, %{pid: pid, server_name: __MODULE__, call_opts: call_opts, state: %State{}}}
  end

  setup [:register_name, :make_seen_list]

  defmacro assert_receive_memo(kv_pairs) do
    quote location: :keep, bind_quoted: [kv_pairs: kv_pairs] do
      receive do
        {Alfred, %Memo{} = memo} -> Should.Contain.kv_pairs(memo, kv_pairs)
        error -> refute true, Should.msg(error, "should have received", Memo)
      after
        100 -> refute true, "should have received memo"
      end
    end
  end

  describe "Alfred.Notify.Server starts" do
    test "via applicaton" do
      GenServer.whereis(Server)
      |> Should.Be.Server.with_state()
    end

    test "with specified name", %{server_name: server_name} do
      GenServer.whereis(server_name)
      |> Should.Be.Server.with_state()
    end
  end

  describe "Alfred.Notify.Server.call/2" do
    test "handles when a server is not available" do
      {:foo}
      |> Server.call(notify_server: Foo.Bar)
      |> Should.Be.match({:no_server, Foo.Bar})
    end

    test "handles when the server is available", ctx do
      Server.call(:registrations, ctx.call_opts)
      |> Should.Be.map()
    end
  end

  describe "Alfred.Notify.Server.cast/2" do
    test "honors :notify_server opt", ctx do
      {:notify, []}
      |> Server.cast(ctx.call_opts)
      |> Should.Be.ok()
    end
  end

  describe "Alfred.Notify.Server.handle_call/3" do
    @tag register_name: []
    test "handles {:register, opts} messages", %{ticket: ticket} do
      Should.Be.Struct.named(ticket, Ticket)
    end

    @tag register_name: []
    @tag seen_list: [include_ticket: [ttl_ms: 15_000], count: 100]
    test "handles {:notify, seen_list}", ctx do
      {:notify, ctx.seen_list}
      |> Server.call(ctx.call_opts)
      |> Should.Be.match([ctx.ticket.name])

      assert_receive_memo(name: ctx.ticket.name)
    end

    @tag register_name: []
    test "handles {:unregister, opts} messages", %{ticket: ticket, call_opts: call_opts} do
      {:unregister, ticket.ref}
      |> Server.call(call_opts)
      |> Should.Be.ok()
    end
  end

  describe "Alfred.Notify.Server.handle_cast/2" do
    @tag register_name: []
    @tag seen_list: [include_ticket: [ttl_ms: 15_000], count: 100]
    test "handles {:notify, seen_list}", ctx do
      {:notify, ctx.seen_list}
      |> Server.cast(ctx.call_opts)
      |> Should.Be.ok()

      assert_receive_memo(name: ctx.ticket.name)
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
      assert_receive_memo(name: ctx.ticket.name, missing?: true)
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

    Server.call({:register, register_opts}, call_opts)
    |> Should.Be.Ok.tuple()
    |> Should.Be.Struct.named(Ticket)
    |> tap(fn ticket -> Should.Be.equal(ticket.name, name) end)
    |> tap(fn ticket -> Should.Contain.kv_pairs(ticket.opts, missing_ms: missing_ms) end)
    |> then(fn ticket -> %{ticket: ticket, registered_opts: register_opts} end)
  end

  defp register_name(_), do: :ok

  defp ticket_to_seen_name(%Ticket{} = ticket, opts) do
    ttl_ms = opts[:ttl_ms] || 1000
    seen_at = opts[:seen_at] || DateTime.utc_now()

    %SeenName{name: ticket.name, ttl_ms: ttl_ms, seen_at: seen_at}
  end
end
