defmodule LightDesk.Server do
  @moduledoc """
  LightDesk Controller
  """

  require Logger

  use GenServer, restart: :transient, shutdown: 7000

  #
  # Public API
  #

  def dance(remote, interval),
    do: call({:dance, remote, interval})

  def mode(remote, flag), do: call({:mode_flag, remote, flag})

  def execute_action(action), do: call({:action, action})

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
  def handle_call({:dance, remote, interval}, _from, state) do
    import Remote, only: [tx_payload: 3]

    rc = tx_payload(remote, "lightdesk", %{dance: %{interval_secs: interval}})

    {:reply, rc, state}
  end

  @impl true
  def handle_call({:mode_flag, remote, mode_flag}, _from, state) do
    import Remote, only: [tx_payload: 3]

    rc = tx_payload(remote, "lightdesk", %{mode: %{mode_flag => true}})

    {:reply, rc, state}
  end

  @impl true
  def handle_call({:action, _action} = msg, _from, state) do
    Logger.info(
      "whoops... LightDesk server received: #{inspect(msg, pretty: true)}"
    )

    {:reply, :ok, state}
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
