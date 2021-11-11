defmodule Alfred.Notify.Server.State do
  alias __MODULE__
  alias Alfred.Notify.{Entry, Ticket}
  alias Alfred.Notify.Registration.Key

  defstruct registrations: %{}, started_at: nil

  @type t :: %State{
          registrations: %{optional(Key.t()) => Entry.t()},
          started_at: DateTime.t()
        }

  def new, do: %State{started_at: DateTime.utc_now()}

  def notify(opts, %State{} = s) do
    name = opts[:name]

    for {%Key{name: ^name}, %Entry{} = e} <- s.registrations, reduce: s do
      %State{} = s ->
        Entry.notify(e, opts) |> State.save_notify_to(s)
    end
  end

  def register(opts, %State{} = s) when is_list(opts) do
    pid = opts[:pid]

    try do
      # only link if requested but always monitor
      if opts[:link], do: Process.link(pid)
      monitor_ref = Process.monitor(pid)

      notify_opts = [monitor_ref: monitor_ref] ++ opts
      e = Entry.new(notify_opts) |> Entry.schedule_missing()
      ticket = Ticket.new(e)

      {State.save_notify_to(e, s), {:ok, ticket}}
    catch
      :exit, {:noproc, _} -> {s, {:failed, :no_process_for_pid}}
    end
  end

  def registrations(opts, %State{} = s) do
    all = opts[:all]
    name = opts[:name]

    for {%Key{} = key, %Entry{} = e} <- s.registrations, reduce: [] do
      acc ->
        cond do
          all -> [e, acc] |> List.flatten()
          is_binary(name) and key.name == name -> [e, acc] |> List.flatten()
          true -> acc
        end
    end
  end

  def save_notify_to(%Entry{} = e, %State{} = s) do
    key = %Key{name: e.name, notify_pid: e.pid, ref: e.ref}

    %State{s | registrations: put_in(s.registrations, [key], e)}
  end

  def unregister(ref, %State{} = s) do
    for {%Key{ref: ^ref} = key, e} <- s.registrations, reduce: %State{} do
      acc ->
        Entry.unschedule_missing(e)

        Process.demonitor(e.monitor_ref, [:flush])
        Process.unlink(key.notify_pid)

        %State{s | registrations: Map.delete(acc.registrations, key)}
    end
  end
end
