defmodule Alfred.NotifyServerTest do
  use ExUnit.Case, async: true

  @moduletag alfred: true, alfred_notify_server: true

  setup_all do
    call_opts = [notify_server: __MODULE__]

    assert {:ok, pid} = start_supervised({Alfred.Notify.Server, call_opts})
    assert Process.alive?(pid)

    state = struct(Alfred.Notify.State)

    {:ok, %{pid: pid, server_name: __MODULE__, call_opts: call_opts, state: state}}
  end

  setup [:register_name, :make_seen_list]

  defmacro assert_receive_memo(ticket) do
    quote bind_quoted: [ticket: ticket] do
      assert %Alfred.Notify.Ticket{name: name} = ticket
      assert_receive({Alfred, %Alfred.Notify.Memo{name: ^name}}, 100)
    end
  end

  describe "Alfred.Notify.Server starts" do
    test "via applicaton" do
      pid = GenServer.whereis(Alfred.Notify.Server)
      assert Process.alive?(pid)
    end

    test "with specified name", %{server_name: server_name} do
      pid = GenServer.whereis(server_name)
      assert Process.alive?(pid)
    end
  end

  describe "Alfred.Notify.Server.call/2" do
    test "handles when a server is not available" do
      assert {:no_server, Foo.Bar} = Alfred.Notify.Server.call({:foo}, notify_server: Foo.Bar)
    end

    test "handles when the server is available", ctx do
      assert %{} = Alfred.Notify.Server.call(:registrations, ctx.call_opts)
    end
  end

  describe "Alfred.Notify.Server.cast/2" do
    test "honors :notify_server opt", ctx do
      assert :ok = Alfred.Notify.Server.cast({:notify, []}, ctx.call_opts)
    end
  end

  describe "Alfred.Notify.Server.handle_call/3" do
    @tag register_name: []
    test "handles {:register, opts} messages", %{ticket: ticket} do
      assert %Alfred.Notify.Ticket{} = ticket
    end

    @tag register_name: []
    @tag seen_list: [include_ticket: [ttl_ms: 15_000], count: 100]
    test "handles {:notify, seen_list}", ctx do
      assert %Alfred.Notify.Ticket{name: name} = ticket = ctx.ticket

      assert [^name] = Alfred.Notify.Server.call({:notify, ctx.seen_list}, ctx.call_opts)

      assert_receive_memo(ticket)
    end

    @tag register_name: []
    test "handles {:unregister, opts} messages", %{ticket: ticket, call_opts: call_opts} do
      assert :ok = Alfred.Notify.Server.call({:unregister, ticket.ref}, call_opts)
    end
  end

  describe "Alfred.Notify.Server.handle_cast/2" do
    @tag register_name: []
    @tag seen_list: [include_ticket: [ttl_ms: 15_000], count: 100]
    test "handles {:notify, seen_list}", ctx do
      assert :ok = Alfred.Notify.Server.cast({:notify, ctx.seen_list}, ctx.call_opts)

      assert_receive_memo(ctx.ticket)
    end
  end

  describe "Alfred.Notify.Server.handle_info/2" do
    @tag register_name: []
    test ":DOWN message removes registrations for pid", %{pid: pid, call_opts: call_opts} do
      regs_before = Alfred.Notify.Server.call(:registrations, call_opts) |> map_size()

      Process.send(pid, {:DOWN, make_ref(), :process, self(), :reason}, [])

      regs_after = Alfred.Notify.Server.call(:registrations, call_opts) |> map_size()

      assert regs_after < regs_before
    end

    @tag register_name: [missing_ms: 10]
    test ":missing message sends a missing memo", ctx do
      assert_receive_memo(ctx.ticket)
    end
  end

  defp make_seen_list(%{seen_list: seen_opts} = ctx) do
    include_opts = seen_opts[:include_ticket] ++ [wrap?: true]

    seen_list = if(include_opts != [], do: ticket_to_seen_name(ctx.ticket, include_opts), else: [])
    count = seen_opts[:count] || 0

    %{seen_list: make_multiple_seen_names(seen_list, count)}
  end

  defp make_seen_list(_), do: :ok

  defp make_multiple_seen_names(seen_list, 0), do: seen_list

  defp make_multiple_seen_names(seen_list, count) do
    Enum.reduce(1..count, seen_list, fn _x, acc ->
      fields = [name: Alfred.NamesAid.unique("notifyserver"), ttl_ms: 15_000, seen_at: DateTime.utc_now()]

      [struct(Alfred.SeenName, fields) | acc]
    end)
  end

  defp register_name(%{register_name: opts, call_opts: call_opts}) when is_list(opts) do
    # NOTE: ttl_ms is generally not provided when registering

    name = opts[:name] || Alfred.NamesAid.unique("notifyserver")
    frequency = opts[:frequency] || []
    missing_ms = opts[:missing_ms] || 60_000
    pid = opts[:pid] || self()
    register_opts = [name: name, frequency: frequency, missing_ms: missing_ms, pid: pid] |> Enum.sort()

    assert {:ok, %Alfred.Notify.Ticket{name: ^name, opts: %{missing_ms: ^missing_ms}} = ticket} =
             Alfred.Notify.Server.call({:register, register_opts}, call_opts)

    %{ticket: ticket, registered_opts: register_opts}
  end

  defp register_name(_), do: :ok

  defp ticket_to_seen_name(%Alfred.Notify.Ticket{} = ticket, opts) do
    {seen_opts, rest} = Keyword.split(opts, [:seen_at, :ttl_ms])
    {wrap?, _} = Keyword.pop(rest, :wrap?, false)

    seen_defs = [name: ticket.name, ttl_ms: 1000, seen_at: DateTime.utc_now()]

    fields = Keyword.merge(seen_defs, seen_opts)

    struct(Alfred.SeenName, fields)
    |> then(fn seen_name -> if(wrap?, do: List.wrap(seen_name), else: seen_name) end)
  end
end
