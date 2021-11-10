defmodule Alfred.Notify.Server do
  use GenServer, shutdown: 2000

  require Logger

  alias Alfred.Notify.Entry
  alias Alfred.Notify.Server
  alias Alfred.Notify.Server.State

  @impl true
  def init(_args) do
    State.new() |> reply_ok()
  end

  def start_link(_opts) do
    Logger.debug(["starting ", inspect(Server)])
    GenServer.start_link(__MODULE__, [], name: Server)
  end

  @impl true
  def handle_call({:register, opts}, {pid, _ref}, %State{} = s) when is_list(opts) do
    opts = Keyword.put_new(opts, :pid, pid)
    State.register(opts, s) |> reply()
  end

  @impl true
  def handle_call({:registrations, opts}, _from, %State{} = s) do
    State.registrations(opts, s) |> reply(s)
  end

  @impl true
  def handle_call({:unregister, ref}, _from, %State{} = s) do
    State.unregister(ref, %State{} = s) |> reply(:ok)
  end

  @impl true
  def handle_cast({:just_saw, opts}, %State{} = s) do
    Keyword.put_new(opts, :missing?, false)
    |> State.notify(s)
    |> noreply()
  end

  @impl true
  def handle_info({:missing, %Entry{} = e}, %State{} = s) do
    Logger.debug("MISSING\n#{inspect(e, pretty: true)}")

    Betty.app_error(__MODULE__, name: e.name, missing: true)

    [name: e.name, missing?: true]
    |> State.notify(s)
    |> noreply()
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, %State{} = s) do
    Logger.debug("#{inspect(pid)} exited, removing notify registration(s)")

    State.unregister(ref, s)
    |> noreply()
  end

  ##
  ## GenServer Reply Helpers
  ##

  defp noreply(%State{} = s), do: {:noreply, s}
  defp reply(%State{} = s, val), do: {:reply, val, s}
  defp reply(val, %State{} = s), do: {:reply, val, s}
  defp reply({%State{} = s, val}), do: {:reply, val, s}
  defp reply_ok(%State{} = s), do: {:ok, s}
end
