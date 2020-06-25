defmodule Reef.Captain.Server do
  @moduledoc """
  Orchestration of Reef Activities (e.g. salt mix, cleaning)
  """

  use GenServer, restart: :transient, shutdown: 7000
  use Helen.Module.Config

  alias Reef.DisplayTank.Ato
  alias Reef.MixTank.{Air, Pump, Rodi}

  ##
  ## GenServer Start and Initialization
  ##

  @doc false
  @impl true
  def init(args) do
    import Helen.Time.Helper, only: [epoch: 0]

    # just in case we were passed a map?!?
    args = Enum.into(args, [])

    state = %{
      mode: args[:mode] || :active,
      reef_mode: :started,
      standby_reason: :none,
      last_timeout: epoch(),
      timeouts: 0,
      opts: config_opts(args),
      clean: %{
        status: :never_requested,
        token: 1,
        started_at: epoch(),
        finished_at: epoch()
      },
      fill: %{},
      aerate: %{},
      keep_fresh: %{},
      salt_mix: %{},
      change_prep: %{},
      token: 1
    }

    # opts = state[:opts]

    # should the server start?
    cond do
      state[:mode] == :standby -> :ignore
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
  Bring all reef activities to a stop.

  Returns :ok

  ## Examples

      iex> Reef.Captain.Server.all_stop
      :ok

  """
  @doc since: "0.0.27"
  def all_stop, do: GenServer.call(__MODULE__, {:all_stop})

  @doc """
  Is the server active?

  Returns a boolean.

  ## Examples

      iex> Reef.Temp.Control.active?
      true

  """
  @doc since: "0.0.27"
  def active? do
    case state(:mode) do
      :active -> true
      :standby -> false
    end
  end

  @doc """
  Enable cleaning mode.

  Display tank ato is stopped for the configured clean duration.

  If unconfigured the default is [hours: 2]

  Returns :ok.

  ## Examples

      iex> Reef.Captain.Server.clean()
      :ok

  """
  @doc since: "0.0.27"
  def clean, do: call_if_active({:clean})

  def fill(opts) do
    opts = [opts] |> List.flatten()

    final_opts = config_opts(opts)

    case get_in(final_opts, [:fill]) do
      nil ->
        {:not_configured, :fill}

      _x ->
        call_if_active({:fill, final_opts})
    end
  end

  def last_timeout do
    import Helen.Time.Helper, only: [epoch: 0, utc_now: 0]

    with last <- state(:last_timeout),
         d when d > 0 <- Timex.diff(last, epoch()) do
      Timex.to_datetime(last, "America/New_York")
    else
      _epoch -> epoch()
    end
  end

  @doc """
  Set the mode of the server.

  ## Modes
  When set to `:active` (normal mode) the server will actively control
  the temperature based on the readings of the configured sensor by
  turning on and off the switch.

  If set to `:standby` the server will:
    1. Ensure the switch if off
    2. Continue to receive updates from sensors and switches
    3. Will *not* attempt to control the temperature.

  Returns {:ok, new_mode}

  ## Examples

      iex> Reef.Temp.Control.mode(:standby)
      {:ok, :standby}

  """
  @doc since: "0.0.27"
  def mode(atom) when atom in [:active, :standby] do
    GenServer.call(__MODULE__, {:mode, atom})
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

  def state(keys \\ []) do
    keys = [keys] |> List.flatten()
    state = GenServer.call(__MODULE__, :state)

    case keys do
      [] -> state
      [x] -> Map.get(state, x)
      x -> Map.take(state, [x] |> List.flatten())
    end
  end

  def timeouts, do: state() |> Map.get(:timeouts)

  ##
  ## GenServer handle_* callbacks
  ##

  @doc false
  @impl true
  def handle_call(:state, _from, s), do: reply(s, s)

  @doc false
  @impl true
  def handle_call({:all_stop}, _from, %{opts: _opts} = s) do
    for c <- crew_list() do
      apply(c, :mode, [:standby])
    end

    change_token(s)
    |> reply_and_merge(%{reef_mode: :all_stop}, :ok)
  end

  @doc false
  @impl true
  def handle_call(
        {:clean},
        _from,
        %{
          clean: %{status: _c_mode, token: c_token} = c_map,
          mode: _r_mode,
          opts: opts
        } = s
      ) do
    [{cmd, opts}] = opts[:clean]

    ato_opts = [opts, notify: [:at_start, :at_finish]] |> List.flatten()

    apply_cmd(cmd, Ato, ato_opts)

    c_map = Map.merge(c_map, %{status: :requested, token: c_token + 1})

    reply_and_merge(s, %{clean: c_map}, :ok)
  end

  @doc false
  @impl true
  def handle_call(
        {:fill, final_opts},
        _from,
        %{fill: _, opts: _opts} = s
      ) do
    import Helen.Time.Helper, only: [utc_now: 0, utc_shift: 1, to_ms: 1]

    start_with = final_opts[:start_with] || [:main]
    steps = Keyword.keys(final_opts[:fill])

    max_time_opts = get_in(final_opts, [:fill, start_with, :for])

    run_ms = to_ms(max_time_opts)

    fill_map = %{
      steps: steps,
      start_with: start_with,
      active_step: start_with,
      fill_opts: final_opts,
      start_dt: utc_now(),
      finish_dt: utc_shift(max_time_opts),
      run_ms: run_ms
    }

    merge_map = %{fill: fill_map, reef_mode: :fill}

    change_token(s)
    |> reply_and_merge(merge_map, :ok)
  end

  @doc false
  @impl true
  def handle_continue(:bootstrap, s) do
    noreply(s)
  end

  @doc false
  @impl true
  def handle_info({:gen_device, msg}, s) do
    import Helen.Time.Helper, only: [utc_now: 0]

    msg_puts = fn {cat, cmd, mod} = msg ->
      ["\n => ", inspect(mod), inspect(cat), inspect(cmd)]
      |> Enum.join(" ")
      |> IO.puts()

      msg
    end

    case msg do
      {:at_start, :off, Ato} ->
        c_map = Map.merge(s[:clean], %{started_at: utc_now(), status: :active})

        noreply_and_merge(s, %{clean: c_map})

      {:at_finish, :off, Ato} ->
        rc = Ato.value(:cached)

        c_map =
          Map.merge(s[:clean], %{
            finished_at: utc_now(),
            status: :complete,
            ato_rc: rc
          })

        noreply_and_merge(s, %{clean: c_map})

      msg ->
        msg_puts.(msg)
        noreply(s)
    end
  end

  @doc false
  @impl true
  # handle the case when the msg_token matches the current state.
  def handle_info(
        {:timer, _msg, msg_token},
        %{token: token} = s
      )
      when msg_token == token do
    noreply(s)
  end

  # NOTE:  when the msg_token does not match the state token then
  #        a change has occurred and this off message should be ignored
  def handle_info({:timer, _msg, msg_token}, %{token: token} = s)
      when not msg_token == token do
    noreply(s)
  end

  @doc false
  @impl true
  def handle_info(:timeout, state) do
    state
    |> update_last_timeout()
    |> timeout_hook()
  end

  ##
  ## PRIVATE
  ##

  defp apply_cmd(cmd, mod, opts) do
    case cmd do
      :on -> apply(mod, cmd, [opts])
      :off -> apply(mod, cmd, [opts])
    end
  end

  defp call_if_active(msg) do
    if active?(), do: GenServer.call(__MODULE__, msg), else: {:standby_mode}
  end

  defp crew_list, do: [Air, Pump, Rodi]

  ##
  ## GenServer Receive Loop Hooks
  ##

  defp timeout_hook(%{} = s) do
    noreply(s)
  end

  ##
  ## State Helpers
  ##

  defp change_token(%{} = s), do: update_in(s, [:token], fn x -> x + 1 end)

  defp loop_timeout(%{opts: opts}) do
    import Helen.Time.Helper, only: [to_ms: 2]

    to_ms(opts[:timeout], "PT30.0S")
  end

  # defp state_merge(%{} = s, %{} = map), do: Map.merge(s, map)

  defp update_last_timeout(s) do
    import Helen.Time.Helper, only: [utc_now: 0]

    put_in(s, [:last_timeout], utc_now())
    |> Map.update(:timeouts, 1, &(&1 + 1))
  end

  ##
  ## handle_* return helpers
  ##

  defp noreply(s), do: {:noreply, s, loop_timeout(s)}
  defp noreply_and_merge(s, map), do: {:noreply, Map.merge(s, map)}

  defp reply(s, val) when is_map(s), do: {:reply, val, s, loop_timeout(s)}
  defp reply(val, s), do: {:reply, val, s, loop_timeout(s)}

  defp reply_and_merge(s, m, val) when is_map(s) and is_map(m),
    do: reply(Map.merge(s, m), val)
end
