defmodule Alfred.NotifyStateTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag alfred: true, alfred_notify_state: true

  alias Alfred.NamesAid
  alias Alfred.Notify.{Memo, State, Ticket}
  alias Alfred.SeenName

  defmacro assert_receive_memo_for(ticket) do
    quote location: :keep, bind_quoted: [ticket: ticket] do
      receive do
        {Alfred, %Memo{} = memo} ->
          want_kv = [name: ticket.name, ref: ticket.ref]
          Should.Be.Struct.with_all_key_value(memo, Memo, want_kv)

        error ->
          refute true, Should.msg(error, "should have received Memo")
      after
        100 -> refute true, "should have received memo"
      end
    end
  end

  setup_all do
    state = State.new()

    {:ok, %{state: state}}
  end

  setup [:register_name]

  describe "Alfred.Notify.State.register/2" do
    @tag register: []
    test "adds registration and replies with Ticket", %{state: state, ticket: ticket} do
      Should.Be.Map.with_size(state.registrations, 1)
      Should.Be.struct(ticket, Ticket)
    end

    test "catches non-existant pid", %{state: state} do
      register_opts = [pid: :c.pid(0, 9999, 0), name: NamesAid.unique("notifystate"), link: true]

      want_tuple = {:failed, :no_process_for_pid}

      State.register(register_opts, state)
      |> Should.Be.Tuple.of_types(2, [:struct, {:tuple, 2}])
      |> tap(fn {state, _} -> Should.Be.State.with_key(state, :started_at) end)
      |> tap(fn {_, tuple} -> Should.Be.equal(tuple, want_tuple) end)
    end
  end

  describe "Alfred.Notify.State.notify/2" do
    @tag register: []
    test "finds a registration and notifies", %{state: state, ticket: ticket} do
      utc_now = DateTime.utc_now()
      seen_list = [%SeenName{name: ticket.name, ttl_ms: 10_000, seen_at: utc_now}]

      State.notify(seen_list, state)
      |> Should.Be.Tuple.of_types(2, [:struct, :list])
      |> tap(fn {state, _} -> Should.Be.State.with_key(state, :started_at) end)
      |> tap(fn {_, seen_names} -> Should.Be.equal(seen_names, [ticket.name]) end)

      assert_receive_memo_for(ticket)
    end

    @tag register: []
    test "does not notify when name not registered", %{state: state} do
      utc_now = DateTime.utc_now()
      seen_list = [%SeenName{name: NamesAid.unique("notifystate"), ttl_ms: 10_000, seen_at: utc_now}]

      State.notify(seen_list, state)
      |> Should.Be.Tuple.of_types(2, [:struct, :list])
      |> tap(fn {state, _} -> Should.Be.State.with_key(state, :started_at) end)
      |> tap(fn {_, seen_names} -> Should.Be.List.empty(seen_names) end)

      refute_received {Alfred, _}
    end
  end

  describe "Alfred.Notify.State.unregister/2" do
    @tag register: []
    test "removes the registration for a reference", %{state: state, ticket: ticket} do
      ticket.ref
      |> State.unregister(state)
      |> Should.Be.State.with_key(:registrations)
      |> tap(fn {_state, val} -> Should.Be.Map.empty(val) end)
    end

    @tag register: []
    test "leaves registratons unchanged when reference isn't known", %{state: state} do
      make_ref()
      |> State.unregister(state)
      |> Should.Be.State.with_key(:registrations)
      |> tap(fn {_state, val} -> Should.Be.NonEmpty.map(val) end)
    end
  end

  defp register_name(%{register: opts, state: %State{} = state}) when is_list(opts) do
    # NOTE: ttl_ms is generally not provided when registering

    name = opts[:name] || NamesAid.unique("notifystate")
    frequency = opts[:frequency] || []
    missing_ms = opts[:missing_ms] || 60_000
    pid = opts[:pid] || self()
    register_opts = [name: name, frequency: frequency, missing_ms: missing_ms, pid: pid]

    State.register(register_opts, state)
    |> Should.Be.Tuple.with_size(2)
    |> tap(fn {state, _} -> Should.Be.State.with_key(state, :started_at) end)
    |> tap(fn {_, rc} -> Should.Be.Ok.tuple_with_struct(rc, Ticket) end)
    |> then(fn {state, {:ok, ticket}} -> %{state: state, ticket: ticket} end)
  end

  defp register_name(_), do: :ok
end
