defmodule Reef.Temp.Server do
  @moduledoc """
  Controls the temperature of an environment
  """

  defmacro __using__(use_opts) do
    quote location: :keep, bind_quoted: [use_opts: use_opts] do
      use GenServer, shutdown: 2000

      alias Reef.Temp.Server

      @doc false
      @impl true
      def init(args), do: Server.init(__MODULE__, args)

      @doc false
      def start_link(opts),
        do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

      def ready?, do: Server.ready?(__MODULE__)

      def device_module_map, do: Server.device_module_map(__MODULE__)

      def last_timeout, do: Server.last_timeout(__MODULE__)

      def mode(atom) when atom in [:active, :standby],
        do: Server.mode(__MODULE__, atom)

      def position(opts \\ []), do: Server.position(__MODULE__, opts)

      def restart(opts \\ []), do: Server.restart(__MODULE__, opts)

      def state(keys \\ []), do: Server.state(__MODULE__, keys)

      def temperature, do: Server.temperature(__MODULE__)

      def temperature_ok?, do: Server.temp_ok?(__MODULE__)

      def timeouts, do: state() |> Map.get(:timeouts)

      @doc since: "0.0.29"
      def toggle, do: GenServer.call(__MODULE__, :toggle)

      ##
      ## GenServer handle_* callbacks
      ##

      @doc false
      @impl true
      def handle_call(msg, from, state),
        do: Server.handle_call(__MODULE__, msg, from, state)

      @doc false
      @impl true
      def handle_continue(msg, state),
        do: Server.handle_continue(__MODULE__, msg, state)

      @doc false
      @impl true
      def handle_info(msg, state),
        do: Server.handle_info(__MODULE__, msg, state)

      @doc false
      @impl true
      def terminate(reason, %{opts: _opts} = state),
        do: Server.terminate(__MODULE__, reason, state)
    end
  end

  ##
  ## Reef Temp Server Implementation
  ##

  require Logger

  def init(module, args) do
    # just in case we were passed a map?!?
    args = Enum.into(args, [])

    state = %{
      module: module,
      server_mode: args[:server_mode] || :active,
      last_timeout: nil,
      timeouts: 0,
      opts: args,
      standby_reason: :none,
      ample_msgs: false,
      status: :startup,
      status_at: DateTime.utc_now(),
      devices_seen: :never,
      devices_required: [],
      devices: %{}
    }

    opts = state[:opts]

    # should the server start?
    cond do
      is_nil(opts[:sensor]) -> :ignore
      is_nil(opts[:switch]) -> :ignore
      is_nil(opts[:setpoint]) -> :ignore
      is_nil(opts[:offsets]) -> :ignore
      true -> {:ok, state, {:continue, :bootstrap}}
    end
  end

  @doc """
  Return a map of the device name managed by this worker and the module
  manading the device.

  Useful for creating a map of known "devices" when working with many
  worker managed devices.

  Returns a map.

  """
  @doc since: "0.0.27"
  def device_module_map(module) do
    %{
      name: get_in(state(module, :opts), [:switch, :name]),
      module: module,
      type: :temp_server
    }
  end

  @doc """
  Set the mode of the server.

  ## Modes
  When set to `:active` (normal mode) the server will actively adjust
  the temperature based on the readings of the configured sensor by
  turning on and off the switch.

  If set to `:standby` the server will:
    1. Ensure the switch if off
    2. Continue to receive updates from sensors and switches
    3. Will *not* attempt to adjust the temperature.

  Returns {:ok, new_mode}

  ## Examples

      iex> Reef.Temp.Control.mode(:standby)
      {:ok, :standby}

  """
  @doc since: "0.0.27"
  def mode(module, atom) when atom in [:active, :standby] do
    GenServer.call(module, {:server_mode, atom})
  end

  @doc """
  Returns the position of the switch or an error tuple.  Uses the
  switch name in the configuration.

  ## Examples

      iex> Reef.Temp.Control.position(:simple)
      true

  """
  @doc since: "0.0.27"
  def position(module, opts \\ []) do
    GenServer.call(module, {:position, [opts] |> List.flatten()})
  end

  def handle_call(_module, {:server_mode, mode}, _from, %{opts: opts} = state) do
    off = fn dev_name -> dev_name end

    case mode do
      # when switching to :standby ensure the switch is off
      :standby ->
        dev_name = opts[:switch][:name]

        state
        |> put_in([:server_mode], mode)
        |> put_in([:server_standby_reason], :api)
        |> put_in([:devices, dev_name, :control], off.(dev_name))
        |> reply({:ok, mode})

      # no action when switching to :active, the server will take control
      :active ->
        state
        |> put_in([:server_mode], mode)
        |> put_in([:server_standby_reason], :none)
        |> reply({:ok, mode})
    end
  end

  def handle_call(_module, {:position, opts}, _from, state) do
    position = dev_value(:switch, state)

    if opts == [:simple] do
      case position do
        {:pending, pending} -> pending[:position]
        {:ok, pos} -> pos
        :initializing -> :initializing
        _anything -> :error
      end
      |> reply(state)
    else
      position |> reply(state)
    end
  end

  def handle_call(_module, {:temp_ok?}, _from, %{status: status} = state) do
    case status do
      :in_range -> true |> reply(state)
      _anything_else -> false |> reply(state)
    end
  end

  def handle_call(_module, :temperature, _from, %{opts: _opts} = state) do
    dev_value(:sensor, state) |> reply(state)
  end

  def handle_call(module, :toggle, from, %{server_mode: mode} = state) do
    case mode do
      :standby -> handle_call(module, {:server_mode, :active}, from, state)
      :active -> handle_call(module, {:server_mode, :standby}, from, state)
    end
  end

  def handle_call(_module, :state, _from, s), do: reply(s, s)

  def handle_continue(_module, :bootstrap, state) do
    state
    |> build_and_put_devices_required()
    |> build_and_put_device_maps()
    |> handle_server_startup_mode()
    |> register_for_device_notifications()
    |> noreply()
  end

  def handle_continue(_module, {:control_temperature}, state) do
    state
    |> validate_all_seen()
    |> control_temperature()
    |> noreply()
  end

  def handle_info(_module, {Alfred, _ref, {:notify, dev_name} = obj}, %{opts: _opts} = state) do
    # function to retrieve the value of the device
    value_fn = fn
      :switch -> nil
      :sensor -> nil
    end

    state
    # |> check_pending_cmds_if_needed()
    # ensure the dev_name key contains a map
    |> update_in([:devices, dev_name], fn
      nil -> %{}
      x -> x
    end)
    |> put_in([:devices, dev_name, :obj], obj)
    # stuff the value of the device into the state
    |> put_in([:devices, dev_name, :value], value_fn.(:switch))
    # note when this device was last seen
    |> put_in([:devices, dev_name, :seen], DateTime.utc_now())
    # update the number of messages received for this dev type
    |> update_in([:devices, dev_name, :msg_count], fn
      nil -> 1
      x -> x + 1
    end)
    # update the state and then continue with controlling the temperature
    # NOTE: control_temperature/1 is, during normal operations, called
    #       up to three times.  once for the sensor msg,
    #       again for the switch msg and possibly for the setpoint
    #       match sensor. this behaviour is by design.
    |> continue({:control_temperature})
  end

  def handle_info(_module, :timeout, s) do
    import Helen.Time.Helper, only: [utc_now: 0]

    update_last_timeout(s)
    |> timeout_hook()
  end

  # def handle_info(_mod, {:DOWN, _ref, :process, {mod, _}, reason}, s) do
  #   # if the notification servers are stopping then we should too
  #   case {mod, reason} do
  #     {mod, :shutdown} ->
  #       Logger.debug("shutting down because #{inspect(mod)} has shutdown")
  #       {:stop, :shutdown, s}
  #
  #     {mod, reason} ->
  #       Logger.warn("unhandled :DOWN reason: #{inspect(mod)} #{inspect(reason)}")
  #       noreply(s)
  #   end
  # end

  def terminate(_module, _reason, %{opts: opts}) do
    off = fn dev_name, opts -> {dev_name, opts} end

    switch_name = opts[:switch][:name]

    off.(switch_name, ack: false)
  end

  def last_timeout(module) do
    import Helen.Time.Helper, only: [epoch: 0, utc_now: 0]

    with last <- state(module, :last_timeout),
         d when d > 0 <- Timex.diff(last, epoch()) do
      Timex.to_datetime(last, "America/New_York")
    else
      _epoch -> epoch()
    end
  end

  @doc """
  Is the server ready?

  Returns a boolean.

  ## Examples

      iex> Reef.Temp.Control.ready?
      true

  """
  @doc since: "0.0.27"
  def ready?(module) when is_atom(module) do
    case state(module, :server_mode) do
      :active -> true
      :standby -> false
    end
  end

  @doc """
  Restarts the server via the Supervisor

  ## Examples

      iex> Reef.Temp.Control.restart([])
      :ok

  """
  @doc since: "0.0.27"
  def restart(module, opts) do
    # the Supervisor is the base of the module name with Supervisor appended
    [sup_base | _tail] = Module.split(module)

    sup_mod = Module.concat([sup_base, "Supervisor"])

    if GenServer.whereis(module) do
      Supervisor.terminate_child(sup_mod, module)
    end

    Supervisor.delete_child(sup_mod, module)
    Supervisor.start_child(sup_mod, {module, opts})
  end

  @doc """
  Returns the temperature of the sensor or an error tuple.  Uses the
  sensor name in the configuration.

  ## Examples

      iex> Reef.Temp.Control.temperature()
      75.2

  """
  @doc since: "0.0.27"
  def temperature(module), do: GenServer.call(module, :temperature)

  @doc """
  Returns a boolean indicating if the temperature managed is within the
  defined range.
  """
  @doc since: "0.0.29"
  def temp_ok?(module), do: GenServer.call(module, {:temp_ok?})

  def state(module, keys \\ []) do
    keys = [keys] |> List.flatten()
    state = GenServer.call(module, :state)

    case keys do
      [] -> state
      [x] -> Map.get(state, x)
      x -> Map.take(state, [x] |> List.flatten())
    end
  end

  # def dev_verify_switch_position(state, dev_name, expected_pos, sw_rc_now) do
  #   case sw_rc_now do
  #     {:ok, pos} when pos == expected_pos ->
  #       state
  #       |> update_in([:devices, dev_name], fn x ->
  #         Map.drop(x, [:fault])
  #       end)
  #
  #     {:ok, pos} when pos != expected_pos ->
  #       state
  #       |> put_in([:devices, dev_name, :fault], :position_mismatch)
  #
  #     unmatched ->
  #       state
  #       |> put_in([:devices, dev_name, :fault], unmatched)
  #   end
  # end

  def dev_ample_msgs?(state) do
    # unfold the required_devices and examine the devices seen thus far
    for {_type, required_name, _dev_opts} <- state[:devices_required],
        {dev_name, %{msg_count: msgs}}
        when dev_name == required_name <- state[:devices],
        reduce: true do
      ample when ample == true and msgs >= 1 -> true
      _ample -> false
    end
  end

  def dev_type(device) do
    case device do
      %_{cmds: _} -> :switch
      _x -> :switch
    end
  end

  def dev_value(dev_type, %{opts: opts} = state)
      when dev_type in [:switch, :sensor] do
    dev_name = get_in(opts, [dev_type, :name])

    case get_in(state, [:devices, dev_name, :value]) do
      nil -> :initializing
      x when is_float(x) -> Float.round(x, 1)
      x -> x
    end
  end

  ##
  ## Misc Private Functions
  ##

  # setup can be either a sensor name binary or
  def setpoint_val(%{devices: devices, opts: opts} = _state) do
    setpoint = opts[:setpoint]

    if is_binary(setpoint),
      do: get_in(devices, [setpoint, :value]),
      else: setpoint
  end

  def sensor_opts(x) do
    # handle if passed an opts keyword list or the state
    # if not found in either then default to 30 seconds
    x[:sensor] || x[:opts][:sensor] || [since: "PT30S"]
  end

  # NOTE: obj in the dev_map is the actual Device schema
  def validate_seen(%{obj: obj, seen: seen}, opts) do
    import Helen.Time.Helper, only: [between_ref_and_now: 2, scale: 2]

    case obj do
      # we've not received an obj yet so it can't be seen!
      obj when is_nil(obj) ->
        false

      obj ->
        between_ref_and_now(
          seen,
          get_in(opts, [obj |> dev_type(), :notify_interval])
          |> scale(2)
        )
    end
  end

  def validate_all_seen(%{devices: devices, opts: opts} = state) do
    all_seen =
      for {_dev_name, %{} = dev_map} <- devices, reduce: true do
        false -> false
        accumulate_seen -> accumulate_seen && validate_seen(dev_map, opts)
      end

    state
    |> put_in([:devices_seen], all_seen)
  end

  ##
  ## Control Temperature
  ##

  # start up path (active or standby)
  # to prevent rapid cycling of the switch at startup ensure we have two or more
  # switch or sensor messages before attempting to control the temperature
  def control_temperature(%{ample_msgs: false} = state) do
    if dev_ample_msgs?(state) do
      state
      |> put_in([:ample_msgs], true)
      |> put_in([:status], :nominal)
    else
      state
    end
  end

  # standby mode
  # the server continues to receive updates from sensors and switches
  # but takes no action relative to adjusting the temperature
  def control_temperature(%{server_mode: :standby} = s), do: s

  # happy and normal path, both devices have been seen recently
  def control_temperature(
        %{
          server_mode: :active,
          ample_msgs: true,
          devices_seen: true,
          opts: opts,
          devices: devices
        } = state
      ) do
    import Helen.Time.Helper, only: [utc_now: 0]

    off = fn dev_name -> dev_name end
    on = fn dev_name -> dev_name end

    # grab opts into local variables
    sensor_name = opts[:sensor][:name]
    switch_name = opts[:switch][:name]

    # setpoint and low/high calculations
    set_pt = setpoint_val(state)
    low_temp = set_pt + opts[:offsets][:low]
    high_temp = set_pt + opts[:offsets][:high]

    curr_temp = get_in(devices, [sensor_name, :value])

    cond do
      # in the range, do not adjust heater
      curr_temp >= low_temp and curr_temp < high_temp ->
        state
        |> put_in([:status], :in_range)
        |> put_in([:status_at], utc_now())

      # lower than the set point, needs heating
      curr_temp <= low_temp ->
        state
        |> put_in([:status], :temp_low)
        |> put_in([:status_at], utc_now())
        |> put_in([:devices, switch_name, :control], on.(switch_name))

      # equal to or high than set point, stop heating
      curr_temp >= high_temp ->
        state
        |> put_in([:status], :temp_high)
        |> put_in([:status_at], utc_now())
        |> put_in([:devices, switch_name, :control], off.(switch_name))

      # for minimize risk of overheating, default to heater off
      true ->
        state
        |> put_in([:status], :no_match)
        |> put_in([:status_at], utc_now())
        |> put_in([:devices, switch_name, :control], off.(switch_name))
    end
  end

  # unhappy path, one or both devices are missing
  def control_temperature(%{server_mode: :active, ample_msgs: true, devices_seen: false} = state) do
    import Helen.Time.Helper, only: [utc_now: 0]

    off = fn dev_name -> dev_name end

    switch_name = get_in(state, [:opts, :switch, :name])

    state
    |> put_in([:status], :fault_missing_device)
    |> put_in([:status_at], utc_now())
    |> put_in([:devices, switch_name, :control], off.(switch_name))
  end

  ##
  ## Device Map Helpers
  ##

  def register_for_device_notifications(%{devices_required: devices} = state) do
    check_registration = fn
      {:ok, _} -> nil
      {:failed, msg} -> Logger.debug("failed to register: #{msg}")
    end

    # unfold required devices and register for notification
    for {_type, dev_name, notify_opts} <- devices, reduce: state do
      state ->
        put_rc = fn x -> put_in(state, [:devices, dev_name, :notify_monitor], x) end

        opts = [interval: notify_opts[:notify_interval]]

        Alfred.notify_register(dev_name, opts) |> check_registration.() |> put_rc.()
    end
  end

  ##
  ## State Helpers
  ##

  def build_and_put_devices_required(%{opts: opts} = state) do
    for {k, dev_opts} when k in [:switch, :sensor, :setpoint] <- opts,
        reduce: state do
      state ->
        required_dev =
          case k do
            k when k in [:switch, :sensor] ->
              [{k, dev_opts[:name], dev_opts}]

            k when k == :setpoint and is_binary(dev_opts) ->
              # when setpoint references a sensor use the same notify opts
              # as the primary sensor noting that the name must be updated
              # using the value of :setpoint
              reference_sensor = dev_opts
              dev_opts = opts[:sensor] |> put_in([:name], reference_sensor)
              [{:sensor, reference_sensor, dev_opts}]

            # setpoint is not a reference to a sensor and the empty
            # list will be dropped by List.flatten()
            _k ->
              []
          end

        state
        |> update_in(
          [:devices_required],
          fn x -> [x, required_dev] |> List.flatten() end
        )
    end
  end

  def build_and_put_device_maps(%{devices_required: dev_names} = state) do
    # filter for only binary names to exclude setpoint which is
    # either a fixed value or a reference to a sensor
    for {_type, name, _opts}
        when is_binary(name) <- dev_names,
        reduce: state do
      state ->
        dev_map = %{
          obj: nil,
          value: :initializing,
          seen: :never,
          msg_count: 0,
          notify_monitor: nil
        }

        state
        |> put_in([:devices, name], dev_map)
    end
  end

  def handle_server_startup_mode(%{server_mode: mode} = state) do
    off = fn dev_name -> dev_name end

    case mode do
      :standby ->
        # if the server is starting in :standby ensure the heater is off
        dev_name = get_in(state, [:opts, :switch, :name])

        state
        |> put_in([:standby_reason], :startup_args)
        |> put_in([:devices, dev_name, :control], off.(dev_name))

      :active ->
        state
    end
  end

  def loop_timeout(%{opts: opts}) do
    import Helen.Time.Helper, only: [to_ms: 2]

    to_ms(opts[:timeout], "PT1M30S")
  end

  def update_last_timeout(s) do
    import Helen.Time.Helper, only: [utc_now: 0]

    put_in(s[:last_timeout], utc_now())
    |> Map.update(:timeouts, 1, &(&1 + 1))
  end

  ##
  ## GenServer Receive Loop Hooks
  ##

  def timeout_hook(%{} = s) do
    noreply(s)
  end

  ##
  ## handle_* return helpers
  ##

  def continue(s, msg), do: {:noreply, s, {:continue, msg}}
  def noreply(s), do: {:noreply, s, loop_timeout(s)}
  def reply(s, val) when is_map(s), do: {:reply, val, s, loop_timeout(s)}
  def reply(val, s), do: {:reply, val, s, loop_timeout(s)}
end
