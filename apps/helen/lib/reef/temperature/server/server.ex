defmodule Reef.Temp.Server do
  @moduledoc """
  Controls the temperature of an environment using the readings of a
  Sensor to control a Switch
  """

  defmacro __using__(use_opts) do
    quote location: :keep, bind_quoted: [use_opts: use_opts] do
      use GenServer, restart: :transient, shutdown: 7000

      ##
      ## GenServer Start and Initialization
      ##

      @doc false
      @impl true
      def init(args) do
        import Helen.Time.Helper, only: [utc_now: 0]

        # just in case we were passed a map?!?
        args = Enum.into(args, [])

        state = %{
          server_mode: args[:server_mode] || :active,
          last_timeout: nil,
          timeouts: 0,
          opts: args,
          standby_reason: :none,
          ample_msgs: false,
          status: :startup,
          status_at: utc_now(),
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

      @doc false
      def start_link(opts) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      ##
      ## Public API
      ##

      @doc """
      Is the server ready?

      Returns a boolean.

      ## Examples

          iex> Reef.Temp.Control.ready?
          true

      """
      @doc since: "0.0.27"
      def ready? do
        case state(:server_mode) do
          :active -> true
          :standby -> false
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
      def device_module_map do
        %{name: get_in(state(:opts), [:switch, :name]), module: __MODULE__}
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
      def mode(atom) when atom in [:active, :standby] do
        GenServer.call(__MODULE__, {:server_mode, atom})
      end

      @doc """
      Returns the position of the switch or an error tuple.  Uses the
      switch name in the configuration.

      ## Examples

          iex> Reef.Temp.Control.position(:simple)
          true

      """
      @doc since: "0.0.27"
      def position(opts \\ []) do
        GenServer.call(__MODULE__, {:position, [opts] |> List.flatten()})
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

      @doc """
      Returns the temperature of the sensor or an error tuple.  Uses the
      sensor name in the configuration.

      ## Examples

          iex> Reef.Temp.Control.temperature()
          75.2

      """
      @doc since: "0.0.27"
      def temperature, do: GenServer.call(__MODULE__, :temperature)

      def timeouts, do: state() |> Map.get(:timeouts)

      ##
      ## GenServer handle_* callbacks
      ##

      @doc false
      @impl true
      def handle_call({:server_mode, mode}, _from, %{opts: opts} = state) do
        import Switch, only: [off: 1]

        case mode do
          # when switching to :standby ensure the switch is off
          :standby ->
            dev_name = opts[:switch][:name]

            state
            |> put_in([:server_mode], mode)
            |> put_in([:server_standby_reason], :api)
            |> put_in([:devices, dev_name, :control], off(dev_name))
            |> reply({:ok, mode})

          # no action when switching to :active, the server will take control
          :active ->
            state
            |> put_in([:server_mode], mode)
            |> put_in([:server_standby_reason], :none)
            |> reply({:ok, mode})
        end
      end

      @doc false
      @impl true
      def handle_call({:position, opts}, _from, state) do
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

      @doc false
      @impl true
      def handle_call(:state, _from, s), do: reply(s, s)

      @doc false
      @impl true
      def handle_call(:temperature, _from, %{opts: opts} = state) do
        dev_value(:sensor, state) |> reply(state)
      end

      @doc false
      @impl true
      def handle_continue(:bootstrap, state) do
        state
        |> build_and_put_devices_required()
        |> build_and_put_device_maps()
        |> handle_server_startup_mode()
        |> register_for_device_notifications()
        |> noreply()
      end

      @doc false
      @impl true
      def handle_continue({:control_temperature}, state) do
        state
        |> validate_all_seen()
        |> control_temperature()
        |> noreply()
      end

      @doc false
      @impl true
      def handle_info(
            {:notify, dev_type, %_{name: dev_name} = obj},
            %{opts: opts} = state
          )
          when dev_type in [:sensor, :switch] do
        import Helen.Time.Helper, only: [utc_now: 0]
        import Sensor, only: [fahrenheit: 2]

        # function to retrieve the value of the device
        value_fn = fn
          :switch -> Switch.position(dev_name)
          :sensor -> fahrenheit(dev_name, sensor_opts(opts))
        end

        state
        |> check_pending_cmds_if_needed()
        # ensure the dev_name key contains a map
        |> update_in([:devices, dev_name], fn
          nil -> %{}
          x -> x
        end)
        |> put_in([:devices, dev_name, :obj], obj)
        # stuff the value of the device into the state
        |> put_in([:devices, dev_name, :value], value_fn.(dev_type))
        # note when this device was last seen
        |> put_in([:devices, dev_name, :seen], utc_now())
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

      @doc false
      @impl true
      def handle_info(:timeout, s) do
        import Helen.Time.Helper, only: [utc_now: 0]

        update_last_timeout(s)
        |> timeout_hook()
      end

      @doc false
      @impl true
      def terminate(_reason, %{opts: opts}) do
        import Switch, only: [off: 2]

        switch_name = opts[:switch][:name]

        off(switch_name, ack: false)
      end

      ##
      ## PRIVATE
      ##

      ##
      ## Control Temperature
      ##

      # start up path (active or standby)
      # to prevent rapid cycling of the switch at startup ensure we have two or more
      # switch or sensor messages before attempting to control the temperature
      defp control_temperature(%{ample_msgs: false} = state) do
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
      defp control_temperature(%{server_mode: :standby} = s), do: s

      # happy and normal path, both devices have been seen recently
      defp control_temperature(
             %{
               server_mode: :active,
               ample_msgs: true,
               devices_seen: true,
               opts: opts,
               devices: devices
             } = state
           ) do
        import Helen.Time.Helper, only: [utc_now: 0]
        import Switch, only: [on: 1, off: 1]

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
            |> put_in([:devices, switch_name, :control], on(switch_name))

          # equal to or high than set point, stop heating
          curr_temp >= high_temp ->
            state
            |> put_in([:status], :temp_high)
            |> put_in([:status_at], utc_now())
            |> put_in([:devices, switch_name, :control], off(switch_name))

          # for minimize risk of overheating, default to heater off
          true ->
            state
            |> put_in([:status], :no_match)
            |> put_in([:status_at], utc_now())
            |> put_in([:devices, switch_name, :control], off(switch_name))
        end
      end

      # unhappy path, one or both devices are missing
      defp control_temperature(
             %{server_mode: :active, ample_msgs: true, devices_seen: false} =
               state
           ) do
        import Helen.Time.Helper, only: [utc_now: 0]
        import Switch, only: [off: 1]

        switch_name = get_in(state, [:opts, :switch, :name])

        state
        |> put_in([:status], :fault_missing_device)
        |> put_in([:status_at], utc_now())
        |> put_in([:devices, switch_name, :control], off(switch_name))
      end

      ##
      ## Misc Private Functions
      ##

      # setup can be either a sensor name binary or
      defp setpoint_val(%{devices: devices, opts: opts} = state) do
        setpoint = opts[:setpoint]

        if is_binary(setpoint),
          do: get_in(devices, [setpoint, :value]),
          else: setpoint
      end

      defp sensor_opts(x) do
        # handle if passed an opts keyword list or the state
        # if not found in either then default to 30 seconds
        x[:sensor] || x[:opts][:sensor] || [since: "PT30S"]
      end

      # NOTE: obj in the dev_map is the actual Device schema
      defp validate_seen(%{obj: obj, seen: seen}, opts) do
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

      defp validate_all_seen(%{devices: devices, opts: opts} = state) do
        all_seen =
          for {dev_name, %{} = dev_map} <- devices, reduce: true do
            false -> false
            accumulate_seen -> accumulate_seen && validate_seen(dev_map, opts)
          end

        state
        |> put_in([:devices_seen], all_seen)
      end

      ##
      ## Device Map Helpers
      ##

      defp check_pending_cmds_if_needed(state) do
        import Switch, only: [acked?: 1]

        for {dev_name, %{control: {:pending, pending_info}}} <- state[:devices],
            reduce: state do
          state ->
            refid = pending_info[:refid]

            if acked?(refid) do
              sw_rc_now = Switch.position(dev_name)
              expected = pending_info[:position]

              state
              |> put_in([:devices, dev_name, :control], sw_rc_now)
              |> dev_verify_switch_position(dev_name, expected, sw_rc_now)
            else
              state
            end
        end
      end

      def dev_verify_switch_position(state, dev_name, expected_pos, sw_rc_now) do
        case sw_rc_now do
          {:ok, pos} when pos == expected_pos ->
            state
            |> update_in([:devices, dev_name], fn x ->
              Map.drop(x, [:fault])
            end)

          {:ok, pos} when pos != expected_pos ->
            state
            |> update_in([:devices, dev_name, :fault], :position_mismatch)

          unmatched ->
            state
            |> update_in([:devices, dev_name, :fault], unmatched)
        end
      end

      defp dev_ample_msgs?(state) do
        # unfold the required_devices and examine the devices seen thus far
        for {_type, required_name, _dev_opts} <- state[:devices_required],
            {dev_name, %{msg_count: msgs}}
            when dev_name == required_name <- state[:devices],
            reduce: true do
          ample when ample == true and msgs >= 1 -> true
          _ample -> false
        end
      end

      defp dev_type(device) do
        case device do
          %_{cmds: _} -> :switch
          _x -> :switch
        end
      end

      defp dev_value(dev_type, %{opts: opts} = state)
           when dev_type in [:switch, :sensor] do
        dev_name = get_in(opts, [dev_type, :name])

        case get_in(state, [:devices, dev_name, :value]) do
          nil -> :initializing
          x when is_float(x) -> Float.round(x, 1)
          x -> x
        end
      end

      defp register_for_device_notifications(
             %{devices_required: devices} = state
           ) do
        # unfold required devices and register for notification
        for {type, dev_name, notify_opts}
            when type in [:sensor, :switch] <- devices,
            reduce: state do
          state ->
            rc =
              case type do
                :switch -> Switch.notify_register(notify_opts)
                :sensor -> Sensor.notify_register(notify_opts)
              end

            state
            |> put_in([:devices, dev_name, :notify_monitor], rc)
        end
      end

      ##
      ## State Helpers
      ##

      defp build_and_put_devices_required(%{opts: opts} = state) do
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

      defp build_and_put_device_maps(%{devices_required: dev_names} = state) do
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

      defp handle_server_startup_mode(%{server_mode: mode} = state) do
        import Switch, only: [off: 1]

        case mode do
          :standby ->
            # if the server is starting in :standby ensure the heater is off
            dev_name = get_in(state, [:opts, :switch, :name])

            state
            |> put_in([:standby_reason], :startup_args)
            |> put_in([:devices, dev_name, :control], off(dev_name))

          :active ->
            state
        end
      end

      defp loop_timeout(%{opts: opts}) do
        import Helen.Time.Helper, only: [to_ms: 2]

        to_ms(opts[:timeout], "PT1M30S")
      end

      defp update_last_timeout(s) do
        import Helen.Time.Helper, only: [utc_now: 0]

        put_in(s[:last_timeout], utc_now())
        |> Map.update(:timeouts, 1, &(&1 + 1))
      end

      ##
      ## GenServer Receive Loop Hooks
      ##

      defp timeout_hook(%{} = s) do
        noreply(s)
      end

      ##
      ## handle_* return helpers
      ##

      defp continue(s, msg), do: {:noreply, s, {:continue, msg}}
      defp noreply(s), do: {:noreply, s, loop_timeout(s)}
      defp reply(s, val) when is_map(s), do: {:reply, val, s, loop_timeout(s)}
      defp reply(val, s), do: {:reply, val, s, loop_timeout(s)}
    end
  end
end
