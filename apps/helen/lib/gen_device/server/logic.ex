defmodule GenDevice.Logic do
  @moduledoc false

  @callback execute_action(map()) :: tuple()
  @callback faults(term() | list()) :: term()
  @callback faults? :: boolean()
  @callback last_timeout :: term()
  @callback ready? :: boolean()
  @callback restart(list()) :: term()
  @callback runtime_opts :: map()
  @callback server(atom()) :: atom()
  @callback status :: map()
  @callback standby? :: boolean()
  @callback timeout_hook(map()) :: map()

  defmacro __using__(use_opts) do
    quote location: :keep, bind_quoted: [use_opts: use_opts] do
      @behaviour GenDevice.Logic

      alias GenDevice.{Logic, State}
      alias Helen.Worker.State.Common

      @doc false
      def call(msg) do
        if server_down?() do
          {:failed, :server_down}
        else
          GenServer.call(__MODULE__, msg)
        end
      end

      def device_module_map, do: call({:inquiry, :device_module_map})

      def execute_action(action), do: call({:action, action})

      def faults?, do: call({:inquiry, :faults?})
      def faults(what), do: call({:inquiry, {:faults, what}})

      @doc false
      @impl true
      def handle_call({:action, action}, from, state),
        do: Logic.handle_action(action, from, state)

      @doc false
      @impl true
      def handle_call({call, _args} = msg, _from, state)
          when call in [:inquiry, :server_mode, :state],
          do: Logic.handle_call(msg, state)

      @doc false
      @impl true
      def handle_continue(:bootstrap, state) do
        state
        |> Common.change_token()
        |> Logic.noreply()
      end

      @doc false
      @impl true
      def handle_info(:timeout, state) do
        state
        |> Common.update_last_timeout()
        |> timeout_hook()
      end

      @doc false
      def handle_info(msg, state), do: Logic.handle_info(msg, state)

      @doc """
      Return the DateTime of the last GenDevice server timeout
      """
      @doc since: "0.0.27"
      def last_timeout, do: call({:inquiry, :last_timeout})

      @doc """
      Is the server ready?

      Returns true if server is ready, false if server is in standby mode.
      """
      @doc since: "0.0.27"
      def ready?, do: call({:inquiry, :ready?})

      @doc """
      Restarts the server via the Supervisor

      ## Examples

          iex> Roost.Server.restart([])
          :ok

      """
      @doc since: "0.0.27"
      def restart(opts \\ []), do: Logic.restart(__MODULE__, opts)

      @doc """
      Return the worker runtime options.
      """
      @doc since: "0.0.27"
      def runtime_opts, do: call({:inquiry, :runtime_opts})

      def server_down?, do: GenServer.whereis(__MODULE__) |> is_nil()

      @doc """
      Set the Worker to ready or standbyy.

      ## Modes
      When set to `:ready` (normal mode) the Worker is ready to start a mode.

      If set to `:standby` the Worker:
        1. Stops all mode activities (aka full stop)
        2. Denies all change mode requests.

      Returns {:ok, new_mode}

      """
      @doc since: "0.0.27"
      def server(atom) when atom in [:ready, :standby],
        do: call({:server_mode, atom})

      def state, do: call({:inquiry, :state})
      def status, do: call({:inquiry, :status})

      def standby?, do: call({:inquiry, :standby?})

      @doc """
      Retrieve the number of GenServer timeouts that have occurred.
      """
      @doc since: "0.0.27"
      def timeouts, do: call({:inquiry, :timeouts})

      def timeout_hook(state) do
        Logic.noreply(state)
      end

      @doc false
      @impl true
      def terminate(_reason, state), do: state

      defoverridable GenDevice.Logic
    end

    ##
    ## END OF USING
    ##
  end

  ##
  ## START OF MODULE
  ##

  import Helen.Worker.State.Common
  import GenDevice.State

  def adjust_device(state) do
    status = inflight_status(state)

    dev_name = device_name(state)
    func = fn cmd -> apply(Switch, cmd, [dev_name]) end

    cond do
      status == :running ->
        # actual device adjustment is done here!
        cmd = action_cmd(state)
        rc = func.(cmd)

        inflight_adjust_result(state, cmd, rc)

      status == :finished and action_then_cmd(state) in [:on, :off] ->
        cmd = action_then_cmd(state)
        rc = func.(cmd)

        inflight_adjust_result(state, cmd, rc)

      true ->
        state
    end
  end

  def check_fault_and_reply(state) do
    if faults?(state) do
      {:reply, {:fault, faults_map(state)}, state, loop_timeout(state)}
    else
      {:reply, {:ok, status(state)}, state, loop_timeout(state)}
    end
  end

  @doc """
  Return a map of the device name managed by this GenDevice and the module
  manading the device.

  Useful for creating a map of known "devices" when working with many
  GenDevice managed devices.

  Returns a map.

  ## Examples

      iex> GenDevice.device_module_map
      %{name: "device name", module: Module}

  """
  @doc since: "0.0.27"
  def device_module_map(state) do
    %{name: device_name(state), module: module(state), type: :gen_device}
  end

  def finish_inflight(state) do
    inflight_status(state, :finished)
    |> adjust_device()
    |> notify_if_needed()
    |> inflight_move_to_lasts()
  end

  @doc false
  def handle_action(action, {pid, ref}, state) do
    init_inflight(state, action, pid, ref)
    |> next_status()
    |> check_fault_and_reply()
  end

  def handle_call(msg, state) do
    case msg do
      {:inquiry, what} -> handle_inquiry(what, state)
      {:server_mode, mode} -> handle_server_mode(mode, state)
      {:state, _} -> state |> reply(state)
    end
  end

  def handle_info(msg, state) do
    case msg do
      {:run_for, _action} ->
        run_for_expired(state) |> next_status() |> noreply()

      _no_match ->
        noreply(state)
    end
  end

  # credo:disable-for-next-line
  def handle_inquiry(x, state) do
    case x do
      :device_module_map -> device_module_map(state)
      :faults? -> faults?(state)
      :last_timeout -> last_timeout(state)
      :live_opts -> opts(state, :live)
      :ready? -> ready?(state)
      :runtime_opts -> opts(state, :runtime)
      :state -> state
      :status -> status(state)
      :standby? -> not ready?(state)
      :timeouts -> timeouts(state)
      {:faults, what} -> faults_get(state, what)
      {:value, opts} -> value(state, opts)
    end
    |> reply(state)
  end

  def handle_server_mode(mode, state) do
    case {server_mode(state), mode} do
      # quietly ignore changes to the same mode
      {current, requested} when current == requested ->
        state

      # when switching to :standby ensure the switch is off
      {_current, requested} when requested in [:ready, :standby] ->
        state
        |> change_token()
        |> server_mode(requested)
        |> standby_reason_set(:api)
        |> reply({:ok, mode})
    end
  end

  def init_inflight(state, action, pid, ref) do
    change_token(state)
    |> inflight_store(action)
    |> inflight_copy_token()
    # store the pid and reference included in the call for use later
    |> inflight_put(:from_pid, pid)
    |> inflight_put(:msg_ref, ref)
    |> inflight_status(:received)
  end

  def init_server(mod, args, opts, base_state \\ %{})
      when is_atom(mod) and is_list(args) and is_map(opts) and
             is_map(base_state) do
    state =
      Map.merge(base_state, %{
        module: mod,
        device_name: opts[:device_name] || args[:device_name],
        opts: opts,
        timeouts: %{last: :never, count: 0},
        token: nil,
        token_at: nil
      })

    # initial server mode order of precedence:
    #  1. args passed to Worker server
    #  2. defined in configuratin base section
    #  3. defaults to ready
    server_mode = args[:server_mode] || opts(state, :server_mode) || :ready

    state = server_mode(state, server_mode)

    # should the server start?
    if server_mode(state) == :standby do
      :ignore
    else
      {:ok, state, {:continue, :bootstrap}}
    end
  end

  def next_status(state) do
    case inflight_status(state) do
      :received ->
        start_inflight(state)

      :starting ->
        run_inflight(state)

      :running ->
        if run_for_expired?(state), do: finish_inflight(state), else: state

      :finished ->
        finish_inflight(state)
    end
  end

  def noreply(s), do: {:noreply, s, loop_timeout(s)}

  def notify_if_needed(state) do
    status = inflight_status(state)

    cond do
      status == :running and notify?(state, :at_start) ->
        send_notify(state, :at_start)

      status == :finished and notify?(state, :at_finish) ->
        send_notify(state, :at_finish)

      true ->
        state
    end
  end

  def reply(%{token: _} = s, val),
    do: {:reply, val, s, loop_timeout(s)}

  def reply(val, %{token: _} = s),
    do: {:reply, val, s, loop_timeout(s)}

  def restart(mod, opts) do
    # the Supervisor is the base of the module name with Supervisor appended
    [sup_base | _tail] = Module.split(mod)

    sup_mod = Module.concat([sup_base, "Supervisor"])

    if GenServer.whereis(mod) do
      Supervisor.terminate_child(sup_mod, mod)
    end

    Supervisor.delete_child(sup_mod, mod)
    Supervisor.start_child(sup_mod, {mod, opts})
  end

  def run_for_expired(state) do
    if inflight_token(state) == token(state),
      do: inflight_put(state, :run_for_expired?, true),
      else: state
  end

  def run_inflight(state) do
    inflight_status(state, :running)
    |> adjust_device()
    |> notify_if_needed()
    |> start_run_for_if_needed()
    |> next_status()
  end

  def send_notify(state, at) do
    to_pid = reply_to(state)
    action = action_get(state, [])
    # add :via_msg to signal this action has been processed
    payload =
      {msg_type(state),
       put_in(action, [:via_msg], true) |> put_in([:via_msg_at], at)}

    send(to_pid, payload)

    state
  end

  def status(state) do
    %{
      status:
        case inflight_status(state) do
          status when status in [:finished, :none] -> :ready
          status -> status
        end
    }
  end

  def start_inflight(state) do
    inflight_status(state, :starting)
    |> next_status()
  end

  def start_run_for_if_needed(state) do
    import Process, only: [send_after: 3]
    import Helen.Time.Helper, only: [to_duration: 1, to_ms: 1]

    case cmd_for(state) do
      :none ->
        inflight_status(state, :finished)

      dur when is_struct(dur) or is_binary(dur) ->
        dur = to_duration(dur)

        inflight_put(
          state,
          :run_for_timer,
          send_after(self(), {:run_for, action_get(state, [])}, to_ms(dur))
        )

      _no_match ->
        state
    end
  end

  def value(state, opts) do
    import Switch, only: [position: 1]

    case opts do
      [:simple] ->
        case position(device_name(state)) do
          {:pending, pending} -> pending[:position]
          {:ok, pos} -> pos
          _anything -> :error
        end

      [] ->
        position(device_name(state))

      opts ->
        {:bad_args, opts}
    end
  end

  def msg_puts(state, msg) do
    """
     ==> #{inspect(msg)}

    """
    |> IO.puts()

    state
  end
end
