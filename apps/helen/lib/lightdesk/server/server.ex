defmodule LightDesk.Server do
  @moduledoc """
  LightDesk Controller
  """

  require Logger

  use GenServer, restart: :transient, shutdown: 7000

  #
  # Public API
  #

  def mode(:dance), do: call({:dance})
  def mode(:ready), do: call({:mode_flag, :ready})
  def mode(:stop), do: call({:mode_flag, :stop})

  def remote_host do
    :sys.get_state(__MODULE__) |> get_in([:remote_host])
  end

  def remote_host(new_host) do
    call({:remote_host, new_host})
  end

  #
  # Private API
  #

  @doc false
  def call(msg) do
    if server_down?() do
      {:failed, :server_down}
    else
      GenServer.call(__MODULE__, msg)
    end
  end

  @impl true
  def handle_call({:dance}, _from, state) do
    import Remote, only: [tx_payload: 3]

    %{remote_host: host, dance: %{secs: interval}} = state

    rc = tx_payload(host, "lightdesk", %{dance: %{interval_secs: interval}})

    {:reply, rc, state}
  end

  @impl true
  def handle_call({:mode_flag, mode_flag}, _from, state) do
    import Remote, only: [tx_payload: 3]

    %{remote_host: host} = state

    rc = tx_payload(host, "lightdesk", %{mode: %{mode_flag => true}})

    {:reply, rc, state}
  end

  @impl true
  def handle_call({:remote_host, new_host}, _from, state) do
    state = put_in(state, [:remote_host], new_host)

    {:reply, {:ok, new_host}, state}
  end

  @doc false
  @impl true
  def init(args) do
    import Ecto.UUID, only: [generate: 0]
    import Helen.Time.Helper, only: [utc_now: 0]
    # just in case we were passed a map?!?
    args = Enum.into(args, [])

    state = %{
      module: __MODULE__,
      remote_host: "roost-beta",
      dance: %{secs: 23.3},
      args: args,
      token: generate(),
      token_at: utc_now()
    }

    {:ok, state}
  end

  def server_down?, do: GenServer.whereis(__MODULE__) |> is_nil()

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def state, do: :sys.get_state(__MODULE__)
end
