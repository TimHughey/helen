defmodule Carol.Server do
  @moduledoc false

  require Logger
  use GenServer
  use Alfred, name: [backend: :message], execute: []

  @impl true
  def init(args) do
    state = Carol.State.new(args)

    {:ok, state, {:continue, :bootstrap}}
  end

  @doc """
  Create the child spec map for a server instance

  This function accepts a comingled list of `child_spec` opts and server
  initialization opts.

  The `child_spec` keys are extracted from the list to create the `child_spec`
  map and the remaining keys are passed as initialization opts.

  > Carol.Server initialization opts can not conflict with `child_spec` opts.
  >
  > See `Supervisor.child_spec/2` for the shape and description of a
  > child spec map.

  """
  @doc since: "0.2.0"
  def child_spec(args), do: Carol.Instance.child_spec(args)

  @doc false
  def start_link(start_args) when is_list(start_args) do
    id = start_args[:id]
    server_args = if(id, do: [name: id], else: [])

    GenServer.start_link(__MODULE__, start_args, server_args)
  end

  # GenServer handlers

  @impl true
  def handle_call({:execute_cmd, [_name_info, opts]}, _from, state) do
    {rc, {result, new_state}} = execute_cmd(state, opts)

    # NOTE: invoke tick to handle any changes made by the cmd
    {:reply, {rc, result}, new_state, {:continue, :tick}}
  end

  @impl true
  def handle_call({:status_lookup, [_name_info, opts]}, _from, state) do
    status_lookup = status_lookup(state, opts)

    reply(status_lookup, state)
  end

  @impl true
  def handle_continue(:bootstrap, %{ticket: _} = state) do
    Carol.State.start_notifies(state) |> noreply()
  end

  @impl true
  @tick_steps [:seen_at, :freshen, :register, :align, :next_tick]
  def handle_continue(:tick, %{tick: tick} = state) do
    if is_reference(tick), do: Process.cancel_timer(tick, async: true, info: false)

    Enum.reduce(@tick_steps, state, fn
      :seen_at, state -> Carol.State.seen_at(state)
      :freshen, state -> Carol.State.freshen_episodes(state)
      :register, state -> register(state)
      :align, state -> tap(state, &align_equipment(&1))
      :next_tick, state -> Carol.State.next_tick(state)
    end)
    |> noreply()
  end

  @impl true
  # NOTE: Carol does not register for missing Memos
  def handle_info({Alfred, %Alfred.Memo{} = _memo}, state) do
    # NOTE: reuse :tick to ensure appropriate episode is active
    continue(:tick, state)
  end

  @impl true
  def handle_info(:restart, state), do: {:stop, :normal, state}

  @impl true
  def handle_info(:tick, %Carol.State{} = s) do
    continue(:tick, s)
  end

  # Alfred Callbacks
  @impl true
  def execute_cmd(state, opts) do
    opts_map = Enum.into(opts, %{})

    case opts_map do
      %{cmd: "pause" = cmd} ->
        {:ok, {%{cmd: cmd, sent_at: state.seen_at}, Carol.State.stop_notifies(state)}}

      %{cmd: "restart" = cmd} ->
        {:ok, {%{cmd: cmd, sent_at: state.seen_at}, Carol.State.restart(state)}}

      %{cmd: "resume" = cmd} ->
        {:ok, {%{cmd: cmd, sent_at: state.seen_at}, Carol.State.start_notifies(state)}}

      _ ->
        {:error, {%{}, state}}
    end
  end

  @impl true
  def status_lookup(%{} = state, opts) do
    %{episodes: episodes, equipment: equipment, ticket: ticket} = state

    opts = Carol.State.sched_opts(state) ++ opts ++ [format: :humanized]

    base = Map.take(state, [:name, :seen_at, :ttl_ms])

    status = %{
      active_id: Carol.Episode.active_id(episodes),
      episodes: Carol.Episode.status_from_list(episodes, opts),
      equipment: Alfred.status(equipment, binary: true),
      notify: if(match?({:ok, %{}}, ticket), do: "enabled", else: "disabled")
    }

    Map.put(base, :status, status)
  end

  @doc false
  @first_align :first_align_equipment
  def align_equipment(%{episodes: episodes, equipment: equipment}) do
    force? = Process.get(@first_align, true)
    opts = Carol.State.opts()
    extra_opts = [equipment: equipment, force: force?, notify: false] ++ opts

    args = Carol.Episode.execute_args(episodes, :active, extra_opts)

    alfred = Carol.State.alfred()

    case args do
      {opts, defaults} -> alfred.execute(opts, defaults)
      _ -> nil
    end

    if force?, do: Process.put(@first_align, false)
  end

  # GenServer reply helpers

  @doc false
  def continue(term, %Carol.State{} = state), do: {:noreply, state, {:continue, term}}

  defp noreply(%{} = state) do
    opts = Carol.State.opts()

    reply = {:noreply, state}

    if opts[:echo] == :tick, do: Process.send(opts[:caller], reply, [])

    reply
  end

  defp reply(rc, %Carol.State{} = state), do: {:reply, rc, state}
end
