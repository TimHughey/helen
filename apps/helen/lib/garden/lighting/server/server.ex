defmodule Garden.Lighting.Server do
  @moduledoc """
  Controls the garden lighting.
  """

  use GenServer, restart: :transient, shutdown: 7000
  use Helen.Module.Config

  ##
  ## GenServer Start and Initialization
  ##

  @doc false
  @impl true
  def init(args) do
    import Garden.Lighting.Opts, only: [create_default_config_if_needed: 1]

    # just in case we were passed a map?!?
    args = Enum.into(args, [])

    create_default_config_if_needed(__MODULE__)

    state = %{
      module: __MODULE__,
      server_mode: args[:server_mode] || :active,
      worker_mode: :ready,
      devices: %{},
      server_standby_reason: :none,
      token: nil,
      token_at: nil,
      timeouts: %{last: :never, count: 0},
      opts: config_opts(args)
    }

    # should the server start?
    cond do
      state[:server_mode] == :standby -> :ignore
      true -> {:ok, state, {:continue, :bootstrap}}
    end
  end

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ##
  ## Public API
  ##

  @doc """
  Is the server active?

  Returns a boolean.

  ## Examples

      iex> Garden.Lighting.Server.active?
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
  Return the DateTime of the last GenServer timeout.
  """
  @doc since: "0.0.27"
  def last_timeout do
    import Helen.Time.Helper, only: [epoch: 0, utc_now: 0]

    with last <- x_state(:last_timeout),
         d when d > 0 <- Timex.diff(last, epoch()) do
      Timex.to_datetime(last, "America/New_York")
    else
      _epoch -> epoch()
    end
  end

  @doc """
  Restarts the server via the Supervisor

  ## Examples

      iex> Garden.Lighting.Server.restart([])
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
  Exposed API for Helen.Scheduler to start a job identified by name and
  time of day.
  """
  @doc since: "0.0.27"
  def start_job(job_name, job_tod, token)
      when is_atom(job_name) and is_atom(job_tod) do
    call({:start_job, job_name, job_tod, token})
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
  def timeouts, do: x_state() |> Map.get(:timeouts)

  ##
  ## GenServer handle_* callbacks
  ##

  @doc false
  @impl true
  def handle_call(
        {:start_job, job_atom, job_tod, job_token},
        _from,
        %{token: token} = state
      )
      when job_token == token do
    import Garden.Lighting.Logic, only: [execute_job: 3]

    state
    |> execute_job(job_atom, job_tod)
    |> reply(:ok)
  end

  @doc false
  @impl true
  def handle_call(
        {:start_job, _job_atom, _job_tod, job_token},
        _from,
        %{token: token} = state
      )
      when job_token != token,
      do: state |> reply({:failed, :token_mismatch})

  @doc false
  @impl true
  def handle_call(:state, _from, state) do
    state = update_elapsed(state)
    reply(state, state)
  end

  @doc false
  @impl true
  def handle_call({:server_mode, mode}, _from, state) do
    import Garden.Lighting.Logic, only: [change_token: 1]

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
  def handle_continue(:bootstrap, state) do
    import Garden.Lighting.Logic,
      only: [
        change_token: 1,
        ensure_devices_map: 1,
        schedule_jobs_if_needed: 1,
        validate_all_durations: 1
      ]

    valid_opts? = state |> validate_all_durations()

    case valid_opts? do
      true ->
        state
        |> change_token()
        |> ensure_devices_map()
        |> schedule_jobs_if_needed()
        |> put_in([:worker_mode], :ready)
        |> noreply()

      false ->
        state
        |> put_in([:worker_mode], :not_ready)
        |> put_in([:not_ready_reason], :invalid_opts)
        |> noreply()
    end
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
  ## PRIVATE
  ##

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
    import Garden.Lighting.Logic, only: [schedule_jobs_if_needed: 1]

    state |> schedule_jobs_if_needed() |> noreply()
  end

  ##
  ## State Helpers
  ##

  defp loop_timeout(%{opts: opts}) do
    import Helen.Time.Helper, only: [is_iso_duration?: 1, to_ms: 2]

    if is_iso_duration?(opts[:timeout]),
      do: to_ms(opts[:timeout], "PT30.0S"),
      else: 30_000
  end

  # defp set_all_modes_ready(state) do
  #   import Garden.Lighting.Logic, only: [available_modes: 1]
  #
  #   for m <- available_modes(state), reduce: state do
  #     state -> state |> put_in([m], %{status: :ready})
  #   end
  #   |> put_in([:worker_mode], :ready)
  # end

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

  defp noreply(s), do: {:noreply, s, loop_timeout(s)}

  defp reply(s, val) when is_map(s), do: {:reply, val, s, loop_timeout(s)}
  defp reply(val, s), do: {:reply, val, s, loop_timeout(s)}
end
