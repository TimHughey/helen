defmodule Sequencer.Server do
  @moduledoc """
  Controls mulitple devices based on a series of commands
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
          actions: %{running: %{}},
          opts: config_opts(args)
        }

        opts = state[:opts]

        # should the server start?
        cond do
          is_nil(opts[:group]) -> :ignore
          is_nil(opts[:category]) -> :ignore
          is_nil(opts[:activity]) -> :ignore
          is_nil(opts[:actions]) -> :ignore
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
      Restarts the server via the Supervisor

      ## Examples

          iex> Reef.Temp.Control.restart([])
          :ok

      """
      @doc since: "0.0.27"
      def restart(opts \\ []) do
        if GenServer.whereis(__MODULE__) do
          Supervisor.terminate_child(Reef.Supervisor, __MODULE__)
        end

        Supervisor.delete_child(Reef.Supervisor, __MODULE__)
        Supervisor.start_child(Reef.Supervisor, {__MODULE__, opts})
      end

      @doc """
      Returns the state for diagnostic purposes


      ## Examples

          iex> Sequencer.Server.state([:current, :control])

      """
      @doc since: "0.0.27"

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
      def handle_call({:mode, mode}, _from, %{opts: opts} = s) do
        import Switch, only: [off: 1]

        case mode do
          :standby ->
            nil

          # no action when switching to :active, the server will take control
          true ->
            nil
        end

        state = put_in(s, [:mode], mode)

        reply({:ok, mode}, state)
      end

      @doc false
      @impl true
      def handle_call(:state, _from, s), do: reply(s, s)

      @doc false
      @impl true
      def handle_continue(:bootstrap, s) do
        # sequence_begin(s)
        noreply(s)
      end

      # @doc false
      # @impl true
      # def handle_continue({:control_temperature}, s) do
      #   validate_seen(s)
      #   |> control_temperature()
      #   |> noreply()
      # end

      # @doc false
      # @impl true
      # def handle_info(
      #       {:notify, dev_type, %_{name: n} = obj},
      #       %{opts: opts} = s
      #     )
      #     when dev_type in [:sensor, :switch] do
      #   # function to retrieve the current value of the device
      #   current_fn = fn
      #     :switch -> Switch.position(n)
      #     :sensor -> Sensor.fahrenheit(n, sensor_opts(opts))
      #   end
      #
      #   cond do
      #     # the device name matches one from the configuration
      #     n == get_in(opts, [dev_type, :name]) ->
      #       import TimeSupport, only: [utc_now: 0]
      #
      #       # stuff the actual device struct into :devices
      #       put_in(s, [:devices, dev_type], obj)
      #       # stuff the current value of the device into the state
      #       |> put_in([:current, dev_type], current_fn.(dev_type))
      #       # note when this device was last seen
      #       |> put_in([:seen, dev_type], utc_now())
      #       # update the number of messages received for this dev type
      #       |> update_in([:msg_counts, dev_type], &(&1 + 1))
      #       # update the state and then continue with controlling the temperature
      #       # NOTE: control_temperature/1 is, during normal operations, called
      #       #       twice.  once for the sensor msg and again for the switch msg.
      #       #       this behaviour is by design.
      #       |> continue({:control_temperature})
      #
      #     true ->
      #       noreply(s)
      #   end
      # end

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

      defp noreply(s), do: {:noreply, s, loop_timeout(s)}
      defp reply(val, s), do: {:reply, val, s, loop_timeout(s)}
    end
  end
end
