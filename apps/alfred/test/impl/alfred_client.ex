defmodule Alfred.Test.Client do
  use GenServer
  use Alfred, name: [backend: :message], execute: []

  @impl true
  def init(name) do
    state = %{name: name, nature: :server, register: nil, seen_at: Timex.now(), ttl_ms: 10_000}

    {:ok, state, {:continue, :bootstrap}}
  end

  def start_link(name) do
    GenServer.start_link(__MODULE__, name, restart: :temporary)
  end

  # Test Support
  def name(pid), do: GenServer.call(pid, :name)

  # Alfred Callbacks
  # FIXME: should not need execute_cmd/2 or status_lookup/2 when a server

  def handle_call(:name, _from, state), do: {:reply, state.name, state}

  @impl true
  def handle_call({:execute_cmd, [name_info, opts]}, _from, state) do
    opts = put_in(opts, [:_state_], state)
    execute_cmd = execute_cmd(name_info, opts)

    {:reply, execute_cmd, state}
  end

  @impl true
  def handle_call({:status_lookup, [name_info, opts]}, _from, state) do
    opts = put_in(opts, [:_state_], state)
    status_lookup = status_lookup(name_info, opts)

    {:reply, status_lookup, state}
  end

  @impl true
  def handle_continue(:bootstrap, state) do
    state = register(state)

    {:noreply, state}
  end

  @impl true
  def execute_cmd(_name_info, opts) do
    opts_map = Enum.into(opts, %{})

    case opts_map do
      %{cmd: "state" = cmd, _state_: state} -> {:ok, put_in(state, [:cmd], cmd)}
      _ -> {:errpr, %{}}
    end
  end

  @impl true
  def status_lookup(_name_info, _opts) do
    %{status: %{hello: :doctor}, seen_at: Timex.now()}
  end
end
