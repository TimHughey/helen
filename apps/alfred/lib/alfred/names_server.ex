defmodule Alfred.Names.Server do
  defmodule State do
    alias __MODULE__
    alias Alfred.KnownName

    defstruct known: %{}

    @type name :: String.t()
    @type t :: %__MODULE__{known: %{optional(name()) => KnownName.t()}}

    def all_known(%State{} = s) do
      for {_name, entry} <- s.known, do: entry
    end

    def add_or_update(%State{} = s, %KnownName{} = kn) do
      %State{s | known: put_in(s.known, [kn.name], kn)}
    end

    def delete_name(%State{} = s, name), do: %State{s | known: Map.delete(s.known, name)}

    def lookup(name, %State{} = s), do: get_in(s.known, [name])

    def new, do: %State{}
  end

  ##
  ## Names Server
  ##

  require Logger
  use GenServer, shutdown: 1000

  alias __MODULE__
  alias Alfred.{JustSaw, KnownName}

  @impl true
  def init(_start_args) do
    State.new() |> reply_ok()
  end

  def start_link(_initial_args) do
    GenServer.start_link(Server, [], name: __MODULE__)
  end

  @impl true
  def handle_call({:all_known}, _from, %State{} = s) do
    State.all_known(s)
    |> reply(s)
  end

  @impl true
  def handle_call({:delete, name}, _from, %State{} = s) do
    case State.lookup(name, s) do
      %KnownName{} = kn -> State.delete_name(s, name) |> reply(kn)
      nil -> s |> reply(nil)
    end
  end

  @impl true
  def handle_call({:just_saw, %JustSaw{} = js}, _from, %State{} = s) do
    just_saw(js, s) |> reply()
  end

  @impl true
  def handle_call({:lookup, name}, _from, %State{} = s) do
    State.lookup(name, s)
    |> reply(s)
  end

  @impl true
  def handle_cast({:just_saw, %JustSaw{} = js}, %State{} = s) do
    just_saw(js, s) |> noreply()
  end

  defp just_saw(%JustSaw{} = js, %State{} = s) do
    alias Alfred.Notify
    alias JustSaw.Alias

    for %Alias{} = a <- js.seen_list, reduce: {s, []} do
      {%State{} = s, acc} ->
        kn = KnownName.new(a.name, js.mutable?, a.ttl_ms, js.callback_mod)

        Notify.just_saw(kn)

        state = State.add_or_update(s, kn)
        acc = [a.name] ++ acc

        {state, acc}
    end
  end

  ##
  ## GenServer Reply Helpers
  ##

  # (1 of 2) handle plain %State{}
  defp noreply(%State{} = s), do: {:noreply, s}

  # (2 of 2) support pipeline {%State{}, msg} -- return State and discard message
  defp noreply({%State{} = s, _msg}), do: {:noreply, s}

  # (1 of 4) handle pipeline: %State{} first, result second
  defp reply(%State{} = s, res), do: {:reply, res, s}

  # (2 of 4) handle pipeline: result is first, %State{} is second
  defp reply(res, %State{} = s), do: {:reply, res, s}

  # (3 of 4) assembles a reply based on a tuple (State, result) and rc
  defp reply({%State{} = s, result}, rc), do: {:reply, {rc, result}, s}

  # (4 of 4) assembles a reply based on a tuple {result, State}
  defp reply({%State{} = s, result}), do: {:reply, result, s}

  defp reply_ok(%State{} = s) do
    Logger.debug(["\n", inspect(s, pretty: true), "\n"])

    {:ok, s}
  end
end
