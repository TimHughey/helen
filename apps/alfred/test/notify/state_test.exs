defmodule Alfred.NotifyStateTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag alfred: true, alfred_notify_state: true

  alias Alfred.NamesAid
  alias Alfred.Notify.{Memo, State, Ticket}
  alias Alfred.SeenName

  defmacro should_receive_memo_for(ticket) do
    quote location: :keep, bind_quoted: [ticket: ticket] do
      receive do
        {Alfred, memo} ->
          should_be_struct(memo, Memo)
          should_be_equal(memo.name, ticket.name)
          should_be_equal(memo.ref, ticket.ref)
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
      should_be_map_with_size(state.registrations, 1)
      should_be_struct(ticket, Ticket)
    end

    test "catches non-existant pid", %{state: state} do
      register_opts = [pid: :c.pid(0, 9999, 0), name: NamesAid.unique("notifystate"), link: true]

      result = State.register(register_opts, state)

      {new_state, reply_result} = should_be_tuple_with_size(result, 2)
      should_be_struct(new_state, State)
      should_be_match(reply_result, {:failed, :no_process_for_pid})
    end
  end

  describe "Alfred.Notify.State.notify/2" do
    @tag register: []
    test "finds a registration and notifies", %{state: state, ticket: ticket} do
      utc_now = DateTime.utc_now()
      seen_list = [%SeenName{name: ticket.name, ttl_ms: 10_000, seen_at: utc_now}]

      result = State.notify(seen_list, state)

      {new_state, notified} = should_be_tuple_with_size(result, 2)

      should_be_struct(new_state, State)
      should_be_match(notified, [ticket.name])

      should_receive_memo_for(ticket)
    end

    @tag register: []
    test "does not notify when name not registered", %{state: state} do
      utc_now = DateTime.utc_now()
      seen_list = [%SeenName{name: NamesAid.unique("notifystate"), ttl_ms: 10_000, seen_at: utc_now}]

      result = State.notify(seen_list, state)

      {new_state, notified} = should_be_tuple_with_size(result, 2)

      should_be_struct(new_state, State)
      should_be_match(notified, [])

      refute_received {Alfred, _}
    end
  end

  describe "Alfred.Notify.State.unregister/2" do
    @tag register: []
    test "removes the registration for a reference", %{state: state, ticket: ticket} do
      new_state = State.unregister(ticket.ref, state)
      should_be_struct(new_state, State)

      should_be_empty_map(new_state.registrations)
    end

    @tag register: []
    test "leaves registratons unchanged when reference isn't known", %{state: state} do
      new_state = State.unregister(make_ref(), state)
      should_be_struct(new_state, State)

      should_be_non_empty_map(new_state.registrations)
    end
  end

  defp register_name(%{register: opts, state: %State{} = state}) when is_list(opts) do
    # NOTE: ttl_ms is generally not provided when registering

    name = opts[:name] || NamesAid.unique("notifystate")
    frequency = opts[:frequency] || []
    missing_ms = opts[:missing_ms] || 60_000
    pid = opts[:pid] || self()
    register_opts = [name: name, frequency: frequency, missing_ms: missing_ms, pid: pid]

    result = State.register(register_opts, state)
    {new_state, reply_result} = should_be_tuple_with_size(result, 2)

    should_be_struct(new_state, State)

    ticket = should_be_ok_tuple(reply_result)

    should_be_struct(ticket, Ticket)
    should_be_equal(ticket.name, name)
    should_be_equal(ticket.opts.missing_ms, missing_ms)
    should_be_reference(ticket.ref)

    %{state: new_state, ticket: ticket}
  end

  defp register_name(_), do: :ok
end
