defmodule Alfred.NotifyStateTest do
  use ExUnit.Case, async: true

  @moduletag alfred: true, alfred_notify_state: true

  defmacro assert_receive_memo_for(ticket) do
    quote location: :keep, bind_quoted: [ticket: ticket] do
      assert %Alfred.Notify.Ticket{name: name, ref: ref} = ticket

      assert_receive({Alfred, %Alfred.Notify.Memo{name: name, ref: ref}}, 100)
    end
  end

  setup_all do
    {:ok, %{state: Alfred.Notify.State.new()}}
  end

  setup [:register_name]

  describe "Alfred.Notify.State.register/2" do
    @tag register: []
    test "adds registration and replies with Ticket", %{state: state, ticket: ticket} do
      assert %Alfred.Notify.State{registrations: registrations} = state
      assert map_size(registrations) == 1

      assert %Alfred.Notify.Ticket{} = ticket
    end

    test "catches non-existant pid", %{state: state} do
      register_opts = [pid: :c.pid(0, 9999, 0), name: Alfred.NamesAid.unique("notifystate"), link: true]

      assert {%Alfred.Notify.State{started_at: %DateTime{}}, {:failed, :no_process_for_pid}} =
               Alfred.Notify.State.register(register_opts, state)
    end
  end

  describe "Alfred.Notify.State.notify/2" do
    @tag register: []
    test "finds a registration and notifies", %{state: state, ticket: ticket} do
      assert %Alfred.Notify.Ticket{name: name} = ticket
      seen_list = [%Alfred.SeenName{name: name, ttl_ms: 10_000, seen_at: DateTime.utc_now()}]

      assert {%Alfred.Notify.State{started_at: %DateTime{}}, seen_names} =
               Alfred.Notify.State.notify(seen_list, state)

      assert [seen_name | _] = seen_names

      assert ^name = seen_name

      assert_receive_memo_for(ticket)
    end

    @tag register: []
    test "does not notify when name not registered", %{state: state} do
      seen_fields = [name: Alfred.NamesAid.unique("notifystate"), ttl_ms: 10_000, seen_at: DateTime.utc_now()]
      seen_list = [struct(Alfred.SeenName, seen_fields)]

      assert {%Alfred.Notify.State{started_at: %DateTime{}}, []} =
               Alfred.Notify.State.notify(seen_list, state)

      refute_received {Alfred, _}
    end
  end

  describe "Alfred.Notify.State.unregister/2" do
    @tag register: []
    test "removes the registration for a reference", %{state: state, ticket: ticket} do
      assert %Alfred.Notify.Ticket{ref: ref} = ticket
      assert %Alfred.Notify.State{registrations: registrations} = Alfred.Notify.State.unregister(ref, state)

      assert is_map(registrations)
      assert not is_map_key(registrations, ref)
    end

    @tag register: []
    test "leaves registratons unchanged when reference isn't known", %{state: state} do
      assert %Alfred.Notify.State{registrations: initial_registrations} = state

      unknown_ref = make_ref()

      assert %Alfred.Notify.State{registrations: after_registrations} =
               Alfred.Notify.State.unregister(unknown_ref, state)

      assert initial_registrations == after_registrations
    end
  end

  defp register_name(%{register: opts, state: %Alfred.Notify.State{} = state}) when is_list(opts) do
    # NOTE: ttl_ms is generally not provided when registering

    name = opts[:name] || Alfred.NamesAid.unique("notifystate")
    frequency = opts[:frequency] || []
    missing_ms = opts[:missing_ms] || 60_000
    pid = opts[:pid] || self()
    register_opts = [name: name, frequency: frequency, missing_ms: missing_ms, pid: pid]

    assert {%Alfred.Notify.State{started_at: %DateTime{}} = new_state,
            {:ok, %Alfred.Notify.Ticket{} = ticket}} = Alfred.Notify.State.register(register_opts, state)

    %{state: new_state, ticket: ticket}
  end

  defp register_name(_), do: :ok
end
