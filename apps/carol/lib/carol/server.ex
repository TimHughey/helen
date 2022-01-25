defmodule Carol.Server do
  @moduledoc false

  require Logger
  use GenServer

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
    server_args = [name: start_args[:id]]
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
  def handle_call({action, _opts} = msg, _from, %State{} = s) when action in [:pause, :resume] do
    case msg do
      {:pause, _opts} -> State.stop_notifies(s)
      {:resume, _opts} -> State.start_notifies(s)
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

  @impl true
  def handle_call(msg, _from, %State{} = s) when is_map(msg) do
    _opts = [equipment: s.equipment]

    case msg do
      %{episode: id, cmd: true, params: true} ->
        id
        # Program.cmd(s.programs, id, opts) |> Map.from_struct() |> Map.get(:cmd_params) |> Enum.into([])
    end
    |> reply(s)
  end

  @impl true
  def handle_continue(:bootstrap, %State{ticket: :none} = state) do
    # NOTE: State.refresh_episodes/1 ensures episodes are valid

    state
    |> State.refresh_episodes()
    |> State.start_notifies()
    # NOTE: recurse to validate we have a notify ticket (aka Alfred is running)
    |> continue(:bootstrap)
  end

  @impl true
  def handle_continue(:bootstrap, %State{ticket: {:failed, _}} = state) do
    # NOTE:  handle startup race conditions
    Process.sleep(100)

    State.save_ticket(:none, state)
    |> continue(:bootstrap)
  end

  @impl true
  def handle_continue(:bootstrap, %State{} = state) do
    # NOTE:  we now have a notify ticket so begin normal operatins of
    #  1. receiving notify messages for the equipment
    #  2. handling starting the next episode (via timeout)
    noreply(state, :timeout)
  end

  @impl true
  def handle_continue(:tick, %State{} = state) do
    state
    |> State.refresh_episodes()
    |> execute()
    |> noreply(:timeout)
  end

  @impl true
  def handle_info({Alfred, %Alfred.Memo{missing?: true} = memo}, %State{} = s) do
    [server_name: s.server_name, equipment: memo.name, missing: true]
    |> Betty.app_error_v2(passthrough: s)
    |> State.update_notify_at()
    |> noreply(:timeout)
  end

  @impl true
  def handle_info({Alfred, %Alfred.Memo{}}, %State{} = state) do
    # NOTE: reuse :tick to ensure appropriate episode is active
    state
    |> State.update_notify_at()
    |> continue(:tick)
  end

  @impl true
  def handle_info({Alfred, %Alfred.Broom{} = broom}, %{exec_result: execute} = s) do
    case {broom, execute} do
      {%{refid: refid}, %{detail: %{refid: refid}}} -> State.save_cmd(execute, s)
      mismatch -> tap(s, fn _ -> log_refid_mismatch(mismatch, s) end)
    end
    |> noreply(:timeout)
  end

  @impl true
  def handle_info({:echo, _}, state), do: noreply(state, :timeout)

  @impl true
  def handle_info(:timeout, %State{} = s) do
    continue(:tick, s)
  end

  @doc false
  def execute(%State{episodes: []} = state) do
    State.save_exec_result(:no_episodes, state)
  end

  @doc false
  def execute(%State{} = state) do
    state
    |> assemble_execute_opts()
    |> State.alfred().execute()
    |> State.save_exec_result(state)
    |> tap(fn _ -> Process.put(:first_exec_force, false) end)
  end

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  defp assemble_execute_opts(%State{equipment: equipment, episodes: episodes}) do
    force = Process.get(:first_exec_force, true)

    [equipment: equipment, notify: true, force: force]
    |> Carol.Episode.execute_args(:active, episodes)
  end

  @indent 40
  def log_refid_mismatch({broom, execute}, state) do
    %{refid: b_refid} = broom
    %{detail: %{refid: e_refid}} = execute
    %{episodes: [episode | _]} = state
    active_id = Carol.Episode.active_id(episode)
    active_id = if(is_binary(active_id), do: active_id, else: inspect(active_id))

    details = Enum.map([b_refid, e_refid], fn x -> ["\n", String.pad_leading(x, @indent)] end)
    episode = ["\n", String.pad_leading(active_id, @indent)]
    execute = ["\n", inspect(execute, pretty: true)]

    ["refid mismatch", details, episode, execute]
    |> Logger.warn()
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
