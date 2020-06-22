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
        import TimeSupport, only: [epoch: 0]

        # just in case we were passed a map?!?
        args = Enum.into(args, [])

        state = %{
          mode: args[:mode] || :active,
          last_timeout: epoch(),
          timeouts: 0,
          opts: config_opts(args),
          control: %{sensor: nil, switch: nil, last: nil},
          current: %{sensor: nil, switch: nil},
          devices: %{sensor: nil, switch: nil},
          msg_counts: %{sensor: 0, switch: 0},
          # seen contains the time that each device was seen and if
          # the last seen was within the expected interval in :valid
          seen: %{sensor: nil, switch: nil, valid: {:ok, :ok}}
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
        import TimeSupport, only: [epoch: 0, utc_now: 0]

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
      Returns the current position of the switch or an error tuple.  Uses the
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

          iex> Reef.Temp.Control.restart()
          :ok

      """
      @doc since: "0.0.27"
      def restart do
        Supervisor.terminate_child(Reef.Supervisor, __MODULE__)
        Supervisor.restart_child(Reef.Supervisor, __MODULE__)
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
      Returns the current temperature of the sensor or an error tuple.  Uses the
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
      def handle_call(:position, _from, %{current: %{switch: pos}} = s) do
        reply(pos, s)
      end

      @doc false
      @impl true
      def handle_call(:state, _from, s), do: reply(s, s)

      @doc false
      @impl true
      def handle_call(:temperature, _from, %{current: %{sensor: temp}} = s) do
        reply(temp, s)
      end

      @doc false
      @impl true
      def handle_continue(:bootstrap, s) do
        Switch.notify_register(s[:opts][:switch])
        Sensor.notify_register(s[:opts][:sensor])

        noreply(s)
      end

      @doc false
      @impl true
      def handle_continue({:control_temperature}, s) do
        validate_seen(s)
        |> control_temperature()
        |> noreply()
      end

      @doc false
      @impl true
      def handle_info(
            {:notify, dev_type, %_{name: n} = obj},
            %{opts: opts} = s
          )
          when dev_type in [:sensor, :switch] do
        # function to retrieve the current value of the device
        current_fn = fn
          :switch -> Switch.position(n)
          :sensor -> Sensor.fahrenheit(n, sensor_opts(opts))
        end

        cond do
          # the device name matches one from the configuration
          n == get_in(opts, [dev_type, :name]) ->
            import TimeSupport, only: [utc_now: 0]

            # stuff the actual device struct into :devices
            put_in(s, [:devices, dev_type], obj)
            # stuff the current value of the device into the state
            |> put_in([:current, dev_type], current_fn.(dev_type))
            # note when this device was last seen
            |> put_in([:seen, dev_type], utc_now())
            # update the number of messages received for this dev type
            |> update_in([:msg_counts, dev_type], &(&1 + 1))
            # update the state and then continue with controlling the temperature
            # NOTE: control_temperature/1 is, during normal operations, called
            #       twice.  once for the sensor msg and again for the switch msg.
            #       this behaviour is by design.
            |> continue({:control_temperature})

          true ->
            noreply(s)
        end
      end

      @doc false
      @impl true
      def handle_info(:timeout, s) do
        import TimeSupport, only: [utc_now: 0]

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

      # start up path:
      # to prevent rapid cycling of the switch at startup ensure we have two or more
      # switch or sensor messags before attempting to control the temperature
      defp control_temperature(
             %{msg_counts: %{switch: switch_msgs, sensor: sensor_msgs}} = s
           )
           when switch_msgs <= 1 or sensor_msgs <= 1,
           do: s

      # standby mode
      # the server continues to receive updates from sensors and switches
      # but takes no action relative to controlling the temperature
      defp control_temperature(%{mode: :standby} = s), do: s

      # happy and normal path, both devices have been seen recently
      defp control_temperature(
             %{
               mode: :active,
               opts: opts,
               devices: _devices,
               current: current,
               control: _control,
               seen: %{valid: {:ok, :ok}}
             } = s
           ) do
        import Switch, only: [on: 1, off: 1]

        # grab opts into local variables
        switch_name = opts[:switch][:name]
        set_pt = opts[:setpoint]
        low_temp = set_pt + opts[:offsets][:low]
        high_temp = set_pt + opts[:offsets][:high]

        curr_temp = current[:sensor]

        adjust_pos_if_needed = fn ->
          # NOTE:  the result of this anonymous fn is merged into the state
          cond do
            # in the range, do not adjust heater
            curr_temp >= low_temp and curr_temp < high_temp ->
              %{control: %{latest: :in_range}}

            # lower than the set point, needs heating
            curr_temp <= low_temp ->
              %{control: %{latest: :temp_low, switch: on(switch_name)}}

            # equal to or high than set point, stop heating
            curr_temp >= high_temp ->
              %{control: %{latest: :temp_high, switch: off(switch_name)}}

            # for minimize risk of overheating, default to heater off
            true ->
              %{control: %{latest: :no_match, switch: off(switch_name)}}
          end
        end

        Map.merge(s, adjust_pos_if_needed.())
      end

      # unhappy path, one or both devices are missing
      defp control_temperature(
             %{
               mode: :active,
               opts: opts,
               devices: _devices,
               current: _current,
               control: _control,
               seen: %{valid: {sensor, switch}}
             } = s
           ) do
        import Switch, only: [off: 1, off: 2]

        # grab opts into local variables
        switch_name = opts[:switch][:name]

        flag_missing = fn ->
          cond do
            # for safety, attempt to switch off the device if sensor or switch haven't been seen
            sensor != :ok ->
              %{
                control: %{
                  latest: :sensor_missing,
                  sensor: nil,
                  switch: off(switch_name)
                }
              }

            switch != :ok ->
              %{
                control: %{
                  latest: :switch_missing,
                  switch: off(switch_name, lazy: false)
                }
              }

            true ->
              %{
                control: %{
                  latest: :seen_validation_error,
                  sensor: nil,
                  switch: off(switch_name, lazy: false)
                }
              }
          end
        end

        Map.merge(s, flag_missing.())
      end

      defp sensor_opts(x) do
        # handle if passed an opts keyword list or the state
        # if not found in either then default to 30 seconds
        x[:sensor] || x[:opts][:sensor] || [since: [seconds: 30]]
      end

      def validate_seen(
            %{seen: %{sensor: sensor, switch: switch}, opts: opts} = s
          ) do
        import Helen.Time.Helper, only: [between_ref_and_now: 2]

        validate = fn
          nil, _opts ->
            :stale

          last_seen, opts ->
            case between_ref_and_now(last_seen, opts) do
              x when x == true -> :ok
              _x -> :stale
            end
        end

        fuzzy_interval = fn dev_type ->
          config_opts = get_in(opts, [dev_type, :notify_interval])

          # double the opts to handle intermitent missing devices
          for({k, v} <- config_opts, do: [{k, trunc(v * 2)}])
          |> List.flatten()
        end

        seen_valid =
          {validate.(sensor, fuzzy_interval.(:sensor)),
           validate.(switch, fuzzy_interval.(:switch))}

        put_in(s, [:seen, :valid], seen_valid)
      end

      ##
      ## State Helpers
      ##

      defp loop_timeout(%{opts: opts}) do
        import TimeSupport, only: [list_to_ms: 2]

        list_to_ms(opts[:timeout], minutes: 5)
      end

      defp update_last_timeout(s) do
        import TimeSupport, only: [utc_now: 0]

        put_in(s[:last_timeout], utc_now())
        |> Map.update(:timeouts, 1, &(&1 + 1))
      end

      ##
      ## handle_* return helpers
      ##

      defp continue(s, msg), do: {:noreply, s, {:continue, msg}}
      defp noreply(s), do: {:noreply, s, loop_timeout(s)}
      defp reply(val, s), do: {:reply, val, s, loop_timeout(s)}
    end
  end
end
