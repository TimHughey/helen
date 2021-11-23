defmodule Alfred.Notify.State do
  alias __MODULE__
  alias Alfred.Notify.{Entry, Ticket}
  alias Alfred.Notify.Registration.Key
  alias Alfred.SeenName

  defstruct registrations: %{}, started_at: nil

  @type t :: %State{
          registrations: %{optional(Key.t()) => Entry.t()},
          started_at: DateTime.t()
        }

  def new, do: %State{started_at: DateTime.utc_now()}

  # (1 of 2) do nothing when empty list
  def notify([], %State{} = s), do: {s, []}

  # (2 of 2) seen names, notify registrations
  def notify([%SeenName{} | _] = seen_list, %State{registrations: regs} = state) do
    for %SeenName{name: name} = seen <- seen_list, {%Key{name: ^name}, entry} <- regs, reduce: {state, []} do
      {new_state, notified} ->
        opts = [name: name, ttl_ms: seen.ttl_ms, seen_at: seen.seen_at, missing?: false]

        # return a tuple the server will use to build the reply
        {Entry.notify(entry, opts) |> save_entry(new_state), [name] ++ notified}
    end
  end

  def register(opts, %State{} = s) when is_list(opts) do
    entry = Entry.new(opts)

    {State.save_entry(entry, s), {:ok, Ticket.new(entry)}}
  catch
    :error, :noproc ->
      {s, {:failed, :no_process_for_pid}}
      # end
  end

  def save_entry(%Entry{} = e, %State{} = s) do
    key = %Key{name: e.name, notify_pid: e.pid, ref: e.ref}

    %State{s | registrations: put_in(s.registrations, [key], e)}
  end

  def unregister(ref, %State{registrations: regs} = s) when is_reference(ref) do
    for {%Key{ref: ^ref} = key, entry} <- regs, reduce: s do
      new_state ->
        cleanup_registration(key, entry)

        %State{new_state | registrations: Map.delete(new_state.registrations, key)}
    end
  end

  def unregister(pid, %State{registrations: regs} = state) when is_pid(pid) do
    for {%Key{notify_pid: ^pid} = key, entry} <- regs, reduce: state do
      new_state ->
        cleanup_registration(key, entry)

        %State{new_state | registrations: Map.delete(new_state.registrations, key)}
    end
  end

  defp cleanup_registration(%Key{} = key, %Entry{} = entry) do
    Entry.unschedule_missing(entry)

    Process.demonitor(entry.monitor_ref, [:flush])
    Process.unlink(key.notify_pid)
  end
end
