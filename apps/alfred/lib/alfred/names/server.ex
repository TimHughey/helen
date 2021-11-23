defmodule Alfred.Names.Server do
  require Logger
  use GenServer, shutdown: 1000

  alias __MODULE__
  alias Alfred.KnownName
  alias Alfred.Names.State

  def call(msg, opts)
      when is_list(opts) do
    server = opts[:names_server] || __MODULE__

    try do
      GenServer.call(server, msg)
    rescue
      _ -> {:no_server, server}
    catch
      :exit, _ -> {:no_server, server}
    end
  end

  @impl true
  def init(_start_args) do
    State.new() |> reply_ok()
  end

  def start_link(initial_args) do
    name = initial_args[:names_server] || __MODULE__
    GenServer.start_link(Server, [], name: name)
  end

  @impl true
  def handle_call(:known, _from, %State{} = s) do
    State.all_known(s)
    |> reply(s)
  end

  @impl true
  def handle_call({:delete, name}, _from, %State{} = s) do
    case State.lookup(name, s) do
      %KnownName{valid?: true} = kn -> State.delete_known(name, s) |> reply(kn.name)
      _ -> s |> reply(nil)
    end
  end

  @impl true
  def handle_call({:just_saw, []}, _from, %State{} = s), do: reply([], s)

  @impl true
  def handle_call({:just_saw, [%KnownName{} | _] = known_names}, _from, %State{} = s) do
    # known_names = KnownName.map_to_known_names(js)
    new_state = State.add_or_update_known(known_names, s)

    result = for %KnownName{} = kn <- known_names, do: kn.name

    reply(result, new_state)
  end

  @impl true
  def handle_call({:lookup, name}, _from, %State{} = s) do
    State.lookup(name, s)
    |> reply(s)
  end

  ##
  ## GenServer Reply Helpers
  ##

  # (1 of 2) handle pipeline: %State{} first, result second
  defp reply(%State{} = s, res), do: {:reply, res, s}

  # (2 of 2) handle pipeline: result is first, %State{} is second
  defp reply(res, %State{} = s), do: {:reply, res, s}

  defp reply_ok(%State{} = s) do
    Logger.debug(["\n", inspect(s, pretty: true), "\n"])

    {:ok, s}
  end
end
