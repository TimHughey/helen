defmodule Alfred.Notify.Server do
  use GenServer, shutdown: 2000

  require Logger

  alias Alfred.Notify.Entry
  alias Alfred.Notify.State

  def call(msg, opts)
      when is_list(opts) do
    server = opts[:notify_server] || __MODULE__

    try do
      GenServer.call(server, msg)
    rescue
      _ -> {:no_server, server}
    catch
      :exit, _ -> {:no_server, server}
    end
  end

  def cast(msg, opts)
      when is_list(opts) do
    server = opts[:notify_server] || __MODULE__

    GenServer.cast(server, msg)
  end

  @impl true
  def init(_args) do
    State.new() |> reply_ok()
  end

  def start_link(initial_args) do
    name = initial_args[:notify_server] || __MODULE__
    GenServer.start_link(__MODULE__, [], name: name)
  end

  @impl true
  def handle_call({:notify, seen_list}, _, %State{} = s) when is_list(seen_list) do
    State.notify(seen_list, s) |> reply()
  end

  @impl true
  def handle_call({:register, opts}, {pid, _ref}, %State{} = s) when is_list(opts) do
    opts = Keyword.put_new(opts, :pid, pid)
    State.register(opts, s) |> reply()
  end

  @impl true
  def handle_call(:registrations, _from, %State{} = s) do
    s.registrations |> reply(s)
  end

  @impl true
  def handle_call({:unregister, ref}, _from, %State{} = s) do
    State.unregister(ref, %State{} = s) |> reply(:ok)
  end

  @impl true
  def handle_cast({:notify, seen_list}, %State{} = s) do
    State.notify(seen_list, s) |> noreply_discard_result()
  end

  @impl true
  def handle_info({:missing, %Entry{} = e}, %State{} = s) do
    Logger.debug("MISSING\n#{inspect(e, pretty: true)}")

    Betty.app_error(__MODULE__, name: e.name, missing: true)

    Entry.notify(e, missing?: true)
    |> State.save_entry(s)
    |> noreply()
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %State{} = s) do
    Logger.debug("#{inspect(pid)} exited, removing notify registration(s)")

    State.unregister(pid, s)
    |> noreply()
  end

  ##
  ## GenServer Reply Helpers
  ##

  defp noreply(%State{} = s), do: {:noreply, s}
  defp noreply_discard_result({%State{} = s, _}), do: noreply(s)
  defp reply(%State{} = s, val), do: {:reply, val, s}
  defp reply(val, %State{} = s), do: {:reply, val, s}
  defp reply({%State{} = s, val}), do: {:reply, val, s}
  defp reply_ok(%State{} = s), do: {:ok, s}
end
