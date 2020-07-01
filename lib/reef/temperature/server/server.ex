defmodule Reef.Temp.Server do
  @moduledoc """
  Controls the temperature of an environment using the readings of a
  Sensor to control a Switch
  """

  defmacro __using__(use_opts) do
    quote location: :keep, bind_quoted: [use_opts: use_opts] do
      use GenServer, restart: :transient, shutdown: 7000
      use Helen.Module.Config

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
          last_timeout: nil,
          timeouts: 0,
          opts: config_opts(args),
          ample_msgs: false,
          status: :startup,
          status_at: nil,
          devices_seen: :never,
          devices: %{}
        }

        opts = state[:opts]

        # should the server start?
        cond do
          is_nil(opts[:sensor]) -> :ignore
          is_nil(opts[:switch]) -> :ignore
          is_nil(opts[:setpoint]) -> :ignore
          is_nil(opts[:offsets]) -> :ignore
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
        GenServer.call(__MODULE__, {:mode, atom})
      end

      @doc """
      Returns the position of the switch or an error tuple.  Uses the
      switch name in the configuration.

      ## Examples

          iex> Reef.Temp.Control.position()
          true

      """
      @doc since: "0.0.27"
      def position do
        GenServer.call(__MODULE__, :position)
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
      def handle_call({:mode, mode}, _from, %{opts: opts} = s) do
        import Switch, only: [off: 1]

        case mode do
          # when switching to :standby ensure the switch is off
          :standby ->
            Switch.off(opts[:switch][:name])

          # no action when switching to :active, the server will take control
          true ->
            nil
        end

        state = put_in(s, [:mode], mode)

        reply({:ok, mode}, state)
      end

      @doc false
      @impl true
      def handle_call(:position, _from, %{opts: opts} = state) do
        dev_value(:switch, state) |> reply(state)
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
      def handle_continue(:bootstrap, %{opts: opts} = s) do
        Switch.notify_register(opts[:switch])
        Sensor.notify_register(opts[:sensor])

        # if the set_pt is a binary then it's a sensor name and we want those
        # notifies too
        setpoint = opts[:setpoint]

        if is_binary(setpoint) do
          setpoint_opts = opts[:sensor] |> put_in([:name], setpoint)
          Sensor.notify_register(setpoint_opts)
        end

        noreply(s)
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

        # function to retrieve the value of the device
        value_fn = fn
          :switch -> Switch.position(dev_name)
          :sensor -> Sensor.fahrenheit(dev_name, sensor_opts(opts))
        end

        state
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
        # ensure the control key exists
        |> update_in([:devices, dev_name, :control], fn
          nil -> :startup
          x -> x
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

      ##
      ## GenServer Receive Loop Hooks
      ##

      defp timeout_hook(%{} = s) do
        noreply(s)
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
      defp control_temperature(
             %{ample_msgs: false, devices: devices, opts: opts} = state
           ) do
        setpoint = opts[:setpoint]

        cond do
          # devices is empty, no messages seen yet
          Enum.empty?(devices) ->
            state

          # setpoint points to a sensor, include it in required msg count test
          is_binary(setpoint) and dev_msg_sum(state) > 7 ->
            state |> put_in([:ample_msgs], true)

          # we only have the :sensor and :switch in play
          dev_msg_sum(state) > 5 ->
            state |> put_in([:ample_msgs], true)

          # haven't seen enough messages yet
          true ->
            state
        end
      end

      # standby mode
      # the server continues to receive updates from sensors and switches
      # but takes no action relative to adjusting the temperature
      defp control_temperature(%{mode: :standby} = s), do: s

      # happy and normal path, both devices have been seen recently
      defp control_temperature(
             %{
               mode: :active,
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
            switch_rc = on(switch_name)

            state
            |> put_in([:status], :temp_low)
            |> put_in([:status_at], utc_now())
            |> put_in([:devices, switch_name, :control], switch_rc)

          # equal to or high than set point, stop heating
          curr_temp >= high_temp ->
            switch_rc = off(switch_name)

            state
            |> put_in([:status], :temp_high)
            |> put_in([:status_at], utc_now())
            |> put_in([:devices, switch_name, :control], switch_rc)

          # for minimize risk of overheating, default to heater off
          true ->
            switch_rc = off(switch_name)

            state
            |> put_in([:status], :no_match)
            |> put_in([:status_at], utc_now())
            |> put_in([:devices, switch_name, :control], switch_rc)
        end
      end

      # unhappy path, one or both devices are missing
      defp control_temperature(
             %{mode: :active, ample_msgs: true, devices_seen: false} = state
           ) do
        import Helen.Time.Helper, only: [utc_now: 0]
        import Switch, only: [off: 1]

        switch_name = get_in(state, [:opts, :switch, :name])

        switch_rc = off(switch_name)

        state
        |> put_in([:status], :fault_missing_device)
        |> put_in([:status_at], utc_now())
        |> put_in([:devices, switch_name, :control], switch_rc)
      end

      ##
      ## Misc Private Functions
      ##

      defp dev_type(device) do
        case device do
          %_{cmds: _} -> :switch
          _x -> :switch
        end
      end

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
      defp validate_seen(%{obj: obj, seen: seen}, %{opts: opts} = state) do
        import Helen.Time.Helper, only: [between_ref_and_now: 2, scale: 2]

        check_opts =
          get_in(opts, [dev_type(obj), :notify_interval])
          |> scale(2)

        # # double the opts to handle intermitent missing devices
        # check_opts =
        #   for {k, v} <- dev_opts do
        #     [{k, trunc(v * 2)}]
        #   end
        #   |> List.flatten()

        between_ref_and_now(seen, check_opts)
      end

      defp validate_all_seen(%{devices: devices, opts: opts} = state) do
        for {dev_name, %{} = dev_map} <- devices, reduce: state do
          # first check
          %{devices_seen: seen} = state when seen == :never ->
            state
            |> put_in([:devices_seen], validate_seen(dev_map, state))

          %{devices_seen: seen} = state when is_boolean(seen) ->
            state
            |> put_in([:devices_seen], seen && validate_seen(dev_map, state))
        end
      end

      ##
      ## Device Map Helpers
      ##

      defp dev_msg_sum(%{devices: devices, opts: opts} = state) do
        # when setpoint is binary it points to a reference sensor
        devs_to_sum = [
          opts[:switch][:name],
          opts[:sensor][:name],
          opts[:setpoint]
        ]

        # we use the is_binary/1 guard exclude :setpoint if it's a number
        for dev_name when is_binary(dev_name) <- devs_to_sum, reduce: 1 do
          # if we don't find an expected device then we reset the acc to 0
          # to ensure we're summing the required devices and prevent returning
          # a sum representing only devices seen thus far
          acc -> acc + (get_in(devices, [dev_name, :msg_count]) || acc * -1)
        end
      end

      defp dev_value(%{devices: devices, opts: opts} = state, dev_type)
           when dev_type in [:switch, :sensor, :match_sensor] do
        get_in(devices, [
          case dev_type do
            type when type in [:switch, :sensor] -> get_in(opts, [dev_type])
            :match -> get_in(opts, [:setpoint])
          end,
          :value
        ])
      end

      ##
      ## State Helpers
      ##

      defp loop_timeout(%{opts: opts}) do
        import Helen.Time.Helper, only: [to_ms: 2]

        to_ms(opts[:timeout], "PT5M")
      end

      defp update_last_timeout(s) do
        import Helen.Time.Helper, only: [utc_now: 0]

        put_in(s[:last_timeout], utc_now())
        |> Map.update(:timeouts, 1, &(&1 + 1))
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
