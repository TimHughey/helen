defmodule Roost.Server do
  @moduledoc false

  # @compile {:no_warn_undefined, PulseWidth}

  alias PulseWidth
  use Timex

  use GenServer, restart: :transient, shutdown: 5000

  ##
  ## GenServer init and start
  ##

  @impl true
  def init(args) do
    import Roost.Opts, only: [parsed: 0]

    # just in case we were passed a map?!?
    args = Enum.into(args, [])

    state = %{
      module: __MODULE__,
      server_mode: args[:server_mode] || :active,
      faults: %{init: :ok},
      mode: :ready,
      devices: %{},
      dance: :init,
      server_standby_reason: :none,
      token: nil,
      token_at: nil,
      stage: %{},
      timeouts: %{last: :never, count: 0},
      opts: parsed()
    }

    # should the server start?
    if state[:server_mode] == :standby do
      :ignore
    else
      {:ok, state, {:continue, :bootstrap}}
    end
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  ##
  ## Public API
  ##

  @doc """
  Is the server active?

  Returns a boolean.

  ## Examples

      iex> Reef.FirstMate.Server.active?
      true

  """
  @doc since: "0.0.27"
  def active? do
    case x_state() do
      %{server_mode: :standby, worker_mode: _} -> false
      %{server_mode: _, worker_mode: :not_ready} -> false
      _else -> true
    end
  end

  @doc """
  Bring all Roost activities to a stop.

  Returns :ok

  ## Examples

      iex> Roost.Server.all_stop
      :ok

  """
  @doc since: "0.0.27"
  def all_stop, do: call({:all_stop})

  @doc """
  Return a list of available reef modes.

  Returns a list.

  ## Examples

      iex> Reef.FirstMate.Server.available_modes()
      [:keep_fresh, :prep_for_change]

  """
  @doc since: "0.0.27"
  def available_modes, do: call({:available_modes})

  @doc """
  Set the FirstMate to a specific mode.
  """
  @doc since: "0.0.27"
  def worker_mode(mode, opts), do: call({:worker_mode, mode, opts})

  @doc since: "0.0.27"
  def cancel_delayed_cmd, do: call({:cancel_delayed_cmd})

  @doc """
  Set the Roost for dancing
  """
  @doc since: "0.0.27"
  def dance_with_me, do: call({:dance})

  @doc """
      Set the Roost to leaving (dancing is over but exit lighting remains)
  """
  @doc since: "0.0.27"
  def leaving(opts \\ "PT10M0.0S"), do: call({:leaving, opts})

  @doc """
  Return the DateTime of the last GenServer timeout.
  """
  @doc since: "0.0.27"
  def last_timeout do
    import Helen.Time.Helper, only: [epoch: 0, utc_now: 0]
    tz = runtime_opts() |> get_in([:timezone]) || "America/New_York"

    with last <- x_state(:last_timeout),
         d when d > 0 <- Timex.diff(last, epoch()) do
      Timex.to_datetime(last, tz)
    else
      _epoch -> epoch()
    end
  end

  @doc """
  Return the server runtime options.
  """
  @doc since: "0.0.27"
  def runtime_opts do
    if is_nil(GenServer.whereis(__MODULE__)) do
      []
    else
      GenServer.call(__MODULE__, :state) |> get_in([:opts])
    end
  end

  @doc """
  Restarts the server via the Supervisor

  ## Examples

      iex> Reef.Temp.Control.restart([])
      :ok

  """
  @doc since: "0.0.27"
  def restart(opts \\ []) do
    # the Supervisor is the base of the module name with Supervisor appended
    [sup_base | _tail] = Module.split(__MODULE__)

    sup_mod = Module.concat([sup_base, "Supervisor"])

    if GenServer.whereis(__MODULE__) do
      Supervisor.terminate_child(sup_mod, __MODULE__)
    end

    Supervisor.delete_child(sup_mod, __MODULE__)
    Supervisor.start_child(sup_mod, {__MODULE__, opts})
  end

  @doc """
  Set the mode of the server.

  ## Modes
  When set to `:active` (normal mode) the server is ready for reef commands.

  If set to `:standby` the server will:
    1. Take all crew members offline
    2. Denies all reef command mode requeests

  Returns {:ok, new_mode}

  ## Examples

      iex> Reef.Captain.Server(:standby)
      {:ok, :standby}

  """
  @doc since: "0.0.27"
  def server_mode(atom) when atom in [:active, :standby] do
    call({:server_mode, atom})
  end

  @doc """
  Return the GenServer state.

  A single key (e.g. :server_mode) or a list of keys (e.g. :worker_mode, :server_mode)
  can be specified and only those keys are returned.
  """
  @doc since: "0.0.27"
  def x_state(keys \\ []) do
    import Helen.Time.Helper, only: [utc_now: 0]

    if is_nil(GenServer.whereis(__MODULE__)) do
      :DOWN
    else
      keys = [keys] |> List.flatten()

      state =
        GenServer.call(__MODULE__, :state)
        |> Map.drop([:opts])
        |> put_in([:state_at], utc_now())

      case keys do
        [] -> state
        [x] -> Map.get(state, x)
        x -> Map.take(state, [x] |> List.flatten())
      end
    end
  end

  @doc """
  Retrieve the number of GenServer timeouts that have occurred.
  """
  @doc since: "0.0.27"
  def timeouts, do: x_state() |> get_in([:timeouts])

  ##
  ## Roost Public API
  ##

  @doc false
  @impl true
  def handle_call(:state, _from, state) do
    state = state |> update_elapsed()

    state |> reply(state)
  end

  @impl true
  def handle_call({:all_stop}, _from, state) do
    alias Roost.Logic

    state
    |> Logic.all_stop()
    |> reply(:answering_all_stop)
  end

  @doc false
  @impl true
  def handle_call({:available_modes}, _from, state) do
    import Roost.Logic, only: [available_modes: 1]

    reply(state, state |> available_modes())
  end

  @doc false
  @impl true
  def handle_call({:cancel_delayed_cmd}, _from, state) do
    import Roost.Logic, only: [change_token: 1]

    timer = get_in(state, [:pending, :delayed])

    if is_reference(timer), do: Process.cancel_timer(timer)

    state
    |> put_in([:pending], %{})
    |> reply(:ok)
  end

  @doc false
  @impl true
  def handle_call({:server_mode, mode}, _from, state) do
    import Roost.Logic, only: [change_token: 1]

    case mode do
      # when switching to :standby ensure the switch is off
      :standby ->
        state
        |> change_token()
        |> put_in([:server_mode], mode)
        |> put_in([:server_standby_reason], :api)
        |> reply({:ok, mode})

      # no action when switching to :active, the server will take control
      :active ->
        state
        |> change_token()
        |> put_in([:server_mode], mode)
        |> put_in([:server_standby_reason], :none)
        |> reply({:ok, mode})
    end
  end

  @doc false
  @impl true
  def handle_call({:worker_mode, mode, _api_opts}, _from, state) do
    alias Roost.Logic

    state
    |> Logic.init_precheck(mode)
    |> Logic.init_mode()
    |> Logic.start_mode()
    |> check_fault_and_reply()
  end

  @doc false
  @impl true
  def handle_call(msg, _from, state),
    do: state |> msg_puts(msg) |> reply({:unmatched_msg, msg})

  @doc false
  @impl true
  def handle_continue(:bootstrap, state) do
    alias Roost.Logic

    state
    |> Logic.change_token()
    |> Logic.build_devices_map()
    |> set_all_modes_ready()
    |> noreply()
  end

  # handle step via messages
  @impl true
  def handle_info(
        {:msg, {:via_msg, _step}, msg_token} = msg,
        %{token: token} = state
      )
      when msg_token == token do
    alias Roost.Logic

    state
    |> Logic.handle_via_msg(msg)
    |> noreply()
  end

  # handle step via messages
  @impl true
  def handle_info(
        {:msg, {:worker_mode, mode}, msg_token},
        %{token: token} = state
      )
      when msg_token == token do
    alias Roost.Logic

    state
    |> Logic.init_precheck(mode)
    |> Logic.init_mode()
    |> Logic.start_mode()
    |> noreply()
  end

  @impl true
  def handle_info({:msg, _msg, msg_token}, %{token: token} = state)
      when msg_token != token,
      do: state |> noreply()

  @impl true
  def handle_info({:timer, _cmd, msg_token}, %{token: token} = state)
      when msg_token == token do
    state |> noreply()
  end

  # NOTE:  when the msg_token does not match the state token then
  #        a change has occurred and this message should be ignored
  @impl true
  def handle_info({:timer, _msg, msg_token}, %{token: token} = state)
      when msg_token != token do
    state |> noreply()
  end

  @doc false
  @impl true
  def handle_info(:timeout, state) do
    state
    |> update_last_timeout()
    |> timeout_hook()
  end

  @doc false
  @impl true
  def terminate(_reason, %{worker_mode: worker_mode} = state) do
    case worker_mode do
      _nomatch -> state
    end
  end

  ##
  ## Private
  ##

  defp msg_puts(state, msg) do
    """
     ==> #{inspect(msg)}

    """
    |> IO.puts()

    state
  end

  defp update_elapsed(%{worker_mode: mode} = state) do
    import Helen.Time.Helper, only: [elapsed: 2, utc_now: 0]

    if get_in(state, [mode, :status]) do
      now = utc_now()
      started_at = get_in(state, [mode, :started_at])
      step_started_at = get_in(state, [mode, :step, :started_at])

      state
      |> put_in([mode, :elapsed], elapsed(started_at, now))
      |> put_in([mode, :step, :elapsed], elapsed(step_started_at, now))
    else
      state
    end
  end

  ##
  ## GenServer Receive Loop Hooks
  ##

  defp timeout_hook(state) do
    noreply(state)
  end

  ##
  ## State Helpers
  ##

  defp loop_timeout(%{opts: opts}) do
    import Helen.Time.Helper, only: [to_ms: 2]

    to_ms(opts[:timeout], "PT30.0S")
  end

  defp set_all_modes_ready(state) do
    import Roost.Logic, only: [available_modes: 1]

    for m <- available_modes(state), reduce: state do
      state -> state |> put_in([m], %{status: :ready})
    end
    |> put_in([:worker_mode], :ready)
  end

  defp update_last_timeout(state) do
    import Helen.Time.Helper, only: [utc_now: 0]

    state
    |> put_in([:timeouts, :last], utc_now())
    |> update_in([:timeouts, :count], fn x -> x + 1 end)
  end

  ##
  ## GenServer.{call, cast} Helpers
  ##

  defp call(msg) do
    cond do
      server_down?() -> {:failed, :server_down}
      standby?() -> {:failed, :standby_mode}
      true -> GenServer.call(__MODULE__, msg)
    end
  end

  defp server_down? do
    GenServer.whereis(__MODULE__) |> is_nil()
  end

  defp standby? do
    case x_state() do
      %{server_mode: :standby} -> true
      %{server_mode: :active} -> false
      _state -> true
    end
  end

  ##
  ## handle_* return helpers
  ##

  defp check_fault_and_reply(%{fault: fault} = state) do
    {:reply, {:fault, fault}, state, loop_timeout(state)}
  end

  defp check_fault_and_reply(%{worker_mode: worker_mode} = state) do
    {:reply, {:ok, worker_mode}, state, loop_timeout(state)}
  end

  defp noreply(s), do: {:noreply, s, loop_timeout(s)}

  defp reply(s, val) when is_map(s), do: {:reply, val, s, loop_timeout(s)}
  defp reply(val, s), do: {:reply, val, s, loop_timeout(s)}
end
