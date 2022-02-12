defmodule Carol.Server do
  @moduledoc false

  require Logger
  use GenServer
  use Alfred, name: [backend: :message], execute: []

  alias __MODULE__
  alias Carol.State

  @impl true
  def init(args), do: {:ok, Carol.State.new(args), {:continue, :bootstrap}}

  @doc """
  Safely call a server instance

  Wraps a `GenServer.call/3` in a try/catch.

  Returns the result of the `GenServer.call/3` or `{:no_server, server_name}`
  """
  def call(server, msg) when is_pid(server) or is_atom(server) do
    GenServer.call(server, msg)
  rescue
    _ -> {:no_server, server}
  catch
    :exit, _ -> {:no_server, server}
  end

  @doc """
  Create the child spec map for a server instance

  This function accepts a comingled list of `child_spec` opts and server
  initialization opts.

  The `child_spec` keys are extracted from the list to create the `child_spec`
  map and the remaining keys are passed as initialization opts.

  > Server initialization opts can not conflict with `child_spec` opts.
  >
  > See `Supervisor.child_spec/2` for the shape and description of a
  > child spec map.

  """

  def child_spec(args), do: Carol.Instance.child_spec(args)

  @doc false
  def start_link(start_args) when is_list(start_args) do
    id = start_args[:id]
    server_args = if(id, do: [name: id], else: [])

    GenServer.start_link(Server, start_args, server_args)
  end

  # GenServer handlers

  # @impl true
  # def handle_call({:adjust, :cmd_params, params}, _from, %State{} = s) do
  #   s.episodes
  #   |> Episode.adjust_cmd_params(params)
  #   |> State.save_episodes(s)
  #   |> State.analyze_episodes()
  #   |> continue(:ok, :programs)
  # end

  @impl true
  def handle_call({:execute_cmd, [_name_info, opts]}, _from, state) do
    {rc, {result, new_state}} = execute_cmd(state, opts)

    {:reply, {rc, result}, new_state}
  end

  @impl true
  def handle_call({:status_lookup, [_name_info, opts]}, _from, state) do
    status_lookup = status_lookup(state, opts)

    {:reply, status_lookup, state}
  end

  @impl true
  def handle_call({action, _opts} = msg, _from, state) when action in [:pause, :resume] do
    case msg do
      {:pause, _opts} -> State.stop_notifies(state)
      {:resume, _opts} -> State.start_notifies(state)
    end
    |> reply(action)
  end

  @impl true
  def handle_call(action, from, %State{} = s) when action in [:pause, :resume] do
    handle_call({action, []}, from, s)
  end

  @impl true
  @query_msgs [:active_id]
  def handle_call(query, _from, %State{} = s) when query in @query_msgs do
    case query do
      :active_id -> Carol.Episode.active_id(s.episodes)
    end
    |> reply(s)
  end

  @impl true
  def handle_call(:restart, _from, %State{} = s) do
    {:stop, :normal, :restarting, s}
  end

  @impl true
  def handle_call(:state, _from, %State{} = s) do
    Map.from_struct(s) |> reply(s)
  end

  @impl true
  def handle_call({:status, opts}, _from, %State{} = s) do
    opts = State.sched_opts() ++ opts

    Carol.Episode.status_from_list(s.episodes, opts)
    |> reply(s)
  end

  # @impl true
  # def handle_call(msg, _from, %State{} = s) when is_map(msg) do
  #   _opts = [equipment: s.equipment]

  # case msg do
  #   %{episode: id, cmd: true, params: true} ->
  #     id
  # Program.cmd(s.programs, id, opts) |> Map.from_struct() |> Map.get(:cmd_params) |> Enum.into([])
  #   end
  #   |> reply(s)
  # end

  @impl true
  def handle_continue(:bootstrap, %{ticket: _} = state) do
    # NOTE: State.refresh_episodes/1 ensures episodes are valid

    state
    |> State.refresh_episodes()
    |> State.start_notifies()
    |> noreply(:timeout)
  end

  @impl true
  def handle_continue(:tick, state) do
    opts = Carol.State.opts()

    state
    |> State.refresh_episodes()
    |> Carol.State.seen_at()
    |> execute()
    |> register()
    |> tap(fn state -> if opts[:echo] == :tick, do: Process.send(opts[:caller], state, []) end)
    |> noreply(:timeout)
  end

  @impl true
  # NOTE: Carol does not register for missing Memos
  def handle_info({Alfred, %Alfred.Memo{}}, %State{} = state) do
    # NOTE: reuse :tick to ensure appropriate episode is active
    state
    |> State.seen_at()
    |> continue(:tick)
  end

  # NOTE no longer need to handle notify when released
  # @impl true
  # def handle_info({Alfred, %Alfred.Track{}}, state) do
  #   noreply(state, :timeout)
  # end

  @impl true
  def handle_info({:echo, _}, state), do: noreply(state, :timeout)

  @impl true
  def handle_info(:timeout, %State{} = s) do
    continue(:tick, s)
  end

  # Alfred Callbacks
  @impl true
  def execute_cmd(state, opts) do
    opts_map = Enum.into(opts, %{})

    case opts_map do
      %{cmd: "pause" = cmd} ->
        {:ok, {%{cmd: cmd, sent_at: state.seen_at}, Carol.State.stop_notifies(state)}}

      %{cmd: "resume" = cmd} ->
        {:ok, {%{cmd: cmd, sent_at: state.seen_at}, Carol.State.start_notifies(state)}}

      _ ->
        {:error, {%{}, state}}
    end
  end

  @impl true
  def status_lookup(state, _opts) do
    status = %{ticket: state.ticket}

    Map.take(state, [:name, :seen_at, :ttl_ms])
    |> Map.put(:status, status)
  end

  @doc false
  def execute(%{episodes: []} = state), do: state

  @doc false
  def execute(%State{} = state) do
    _ = assemble_execute_opts(state) |> State.alfred().execute()
    _ = Process.put(:first_exec_force, false)

    state
  end

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  defp assemble_execute_opts(%{equipment: equipment, episodes: episodes}) do
    force = Process.get(:first_exec_force, true)

    [equipment: equipment, force: force]
    |> Carol.Episode.execute_args(:active, episodes)
  end

  # GenServer reply helpers

  defp continue(term, %State{} = s), do: {:noreply, s, {:continue, term}}
  defp continue(%State{} = s, term), do: {:noreply, s, {:continue, term}}

  defp noreply(%State{} = s, :timeout), do: {:noreply, s, State.timeout(s)}

  defp reply(%{ticket: ticket} = new_state, action) when action in [:pause, :resume] do
    case ticket do
      x when is_atom(x) -> x
      x when is_struct(x) -> :ok
      _ -> :failed
    end
    |> reply(new_state)
  end

  defp reply(rc, %State{} = s), do: {:reply, rc, s, State.timeout(s)}
end
