defmodule Reef.Temp.Control do
  @moduledoc """
  Controls the temperature of an environment using the readings of a
  Sensor to control a Switch
  """

  use GenServer, restart: :transient, shutdown: 10_000

  ##
  ## GenServer Start and Initialization
  ##

  @doc false
  @impl true
  def init(opts) do
    defaults = [timeout: [minutes: 1]]

    run_opts = Keyword.merge(defaults, opts)

    state = %{opts: run_opts}

    if opts[:autostart] || true do
      {:ok, state, {:continue, :bootstrap}}
    else
      {:ok, state}
    end
  end

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ##
  ## Public API
  ##

  def ensure_started(opts) do
    GenServer.call(self(), {:ensure_started, opts})
  end

  def state, do: :sys.get_state(__MODULE__)

  @doc false
  @impl true
  def handle_continue(:bootstrap, s) do
    import TimeSupport, only: [opts_as_ms: 1]

    ms = s[:opts][:timeout] |> opts_as_ms()

    state = Map.put(s, :timeout_ms, ms)

    {:noreply, state, ms}
  end

  @doc false
  @impl true
  def handle_call({:ensure_started, opts}, _from, s) do
    if s[:started] do
      {:reply, :already_started, s}
    else
      new_opts = Keyword.merge(s[:opts], opts)
      state = Map.put(s, :opts, new_opts)
      {:reply, :starting_now, state, :continue, :bootstrap}
    end
  end

  @doc false
  @impl true
  def handle_info(:timeout, s) do
    state = Map.update(s, :loops, 1, &(&1 + 1))

    {:noreply, state, s[:timeout_ms]}
  end
end
