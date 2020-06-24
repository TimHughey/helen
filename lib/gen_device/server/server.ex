defmodule GenDevice do
  @moduledoc """
  Controls mulitple devices based on a series of commands
  """

  defmacro __using__(use_opts) do
    quote location: :keep, bind_quoted: [use_opts: use_opts] do
      use GenServer, restart: :transient, shutdown: 7000
      use Helen.Module.Config

      @use_opts use_opts

      ##
      ## GenServer Start and Initialization
      ##

      @doc false
      @impl true
      def init(args) do
        import TimeSupport, only: [epoch: 0]

        # just in case we were passed a map?!?
        args = Enum.into(args, [])
        c_opts = Keyword.merge(@use_opts, args)

        state = %{
          mode: args[:mode] || :active,
          device_name: c_opts[:device_name],
          cached_value: nil,
          last_timeout: epoch(),
          lasts: %{cmd: nil, pid: nil},
          active_cmd: nil,
          timeouts: 0,
          opts: c_opts,
          token: 1,
          standby_reason: :none
        }

        opts = state[:opts]

        # should the server start?
        cond do
          is_nil(state[:device_name]) -> :ignore
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
      Switch off the device managed by this server.

      See `GenDevice.on/1` for options.

      Returns :ok or an error tuple

      ## Examples

          iex> GenDevice.off()
          :ok

      """
      @doc since: "0.0.27"
      def off(opts \\ []) when is_list(opts) do
        GenServer.call(__MODULE__, {:off, opts})
      end

      @doc """
      Switch on the device managed by this server.

      Returns :ok or an error tuple

      ## Option Examples
        `for: [minutes: 1]`
          switch the device on for the specified duration

        `at_start: [:notify]`
          send the caller `{:gen_device, :at_start, "switch alias"}` when
          turning on the switch

        `at_finish: [:notify]`
          send the caller `{:gen_device, :at_start, "switch alias"}` when
          turning off the switch

      ## Examples

          iex> GenDevice.on()
          :ok

      """
      @doc since: "0.0.27"
      def on(opts \\ []) when is_list(opts) do
        GenServer.call(__MODULE__, {:on, opts})
      end

      @doc delegate_to: {__MODULE__, :value, 1}
      defdelegate position, to: __MODULE__, as: :value

      @doc """
      Restarts the server via the Supervisor

      ## Examples

          iex> Reef.Temp.Control.restart([])
          :ok

      """
      @doc since: "0.0.27"
      def restart(opts \\ []) do
        # the Supervisor is the first part of the module
        [sup_base | _remainder] = Module.split(__MODULE__)

        sup_mod = Module.concat([sup_base, "Supervisor"])

        if GenServer.whereis(__MODULE__) do
          Supervisor.terminate_child(sup_mod, __MODULE__)
        end

        Supervisor.delete_child(sup_mod, __MODULE__)
        Supervisor.start_child(sup_mod, {__MODULE__, opts})
      end

      @doc """
      Returns the reason the server is in standby mode

      ## Examples

          iex> GenDevice.standby_reason()
          :active | :api_call | :device_does_not_exist

      """
      @doc since: "0.0.27"
      def standby_reason do
        s = state()

        with %{mode: :standby, standby_reason: reason} <- s do
          reason
        else
          %{mode: :active} -> :active
        end
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

      @doc """
      Toggle the devices managed by this server.

      Returns :ok or an error tuple

      ## Examples

          iex> GenServer.toggle()
          :ok

      """
      @doc since: "0.0.27"
      def toggle do
        GenServer.call(__MODULE__, {:toggle})
      end

      @doc """
      Return the current value (position) off the device managed by this server.

      Returns a boolean or an error tuple

      ## Examples

          iex> GenServer.value()
          true

      """
      @doc since: "0.0.27"
      def value(opts \\ []) do
        GenServer.call(__MODULE__, {:value, [opts] |> List.flatten()})
      end

      ##
      ## GenServer handle_* callbacks
      ##

      @doc false
      @impl true
      def handle_call(
            {:mode, mode},
            _from,
            %{device_name: dev_name, opts: opts} = s
          ) do
        import Switch, only: [off: 1]

        update_state_fn = fn
          x when x == :standby ->
            sw_rc = Switch.off(dev_name)
            changes = %{mode: x, standby_reason: :api_call}
            put_in(s, [:mode], x) |> put_in([:standby_reason], :api_call)

          x when x == :active ->
            put_in(s, [:mode], x) |> put_in([:standby_reason], :none)
        end

        reply({:ok, mode}, update_state_fn.(mode))
      end

      @doc false
      @impl true
      def handle_call(:state, _from, s), do: reply(s, s)

      @doc false
      @impl true
      # prevent any actions aside from changing the mode and getting the
      # state (matched above) when in standby
      def handle_call(_msg, _from, %{mode: :standby} = s),
        do: reply(:standby_mode, s)

      @doc false
      @impl true
      def handle_call(
            {cmd, cmd_opts} = msg,
            {pid, _ref},
            %{opts: opts, lasts: lasts, device_name: dev_name} = s
          ) do
        pos_rc = adjust_switch(cmd, dev_name)

        # update the state's cached value, last change and increment the token
        # to invalidate any pending timers
        lasts = Map.merge(lasts, %{cmd: cmd, pid: pid})

        state =
          Map.merge(s, %{lasts: lasts, switch_rc: pos_rc, active_cmd: cmd})
          |> update_in([:token], fn x -> x + 1 end)

        send_at_timer_msg_if_needed(
          {cmd, cmd_opts, pid},
          :at_start,
          dev_name
        )

        with true <- valid_on_off_opts?(cmd_opts),
             {:pending, res} when is_list(res) <- pos_rc,
             {:position, pos} when is_boolean(pos) <- hd(res) do
          schedule_timer_if_needed(state, pid, msg)
        else
          false ->
            reply({:bad_args, cmd_opts}, state)

          {:ok, _pos} ->
            schedule_timer_if_needed(state, pid, msg)

          error ->
            reply(error, state)
        end
      end

      @doc false
      @impl true
      def handle_call({:value, opts}, _from, %{device_name: dev_name} = s) do
        with {:cached, false, true} <- {:cached, opts == [:cached], opts == []},
             # when there are no opts get the current value of the state
             {:ok, pos} = pos_rc <- Switch.position(dev_name),
             # and cache it
             state <- update_state(s, :switch_rc, pos_rc) do
          reply(pos, state)
        else
          # return the cached value when included in the opts
          {:cached, true, false} ->
            s[:cached_value] |> reply(s)

          # unknown opts
          {:cached, false, false} ->
            reply({:bad_args, opts}, s)

          # some error occured, cache and return it
          error ->
            state = update_state(s, :switch_rc, error)
            reply(error, state)
        end
      end

      @doc false
      @impl true
      def handle_continue(:bootstrap, %{device_name: dev_name} = s) do
        import Switch, only: [exists?: 1]

        # if the device does not exist immediately entry standby mode
        # and note the reason
        case exists?(dev_name) do
          true ->
            noreply(s)

          false ->
            map = %{mode: :standby, standby_reason: :device_does_not_exist}
            noreply_merge_state(s, map)
        end
      end

      @doc false
      @impl true
      # handle the case when the msg_token matches the current state.
      def handle_info(
            {:timer, {cmd, cmd_opts, reply_pid} = msg, msg_token},
            %{device_name: dev_name, token: token} = s
          )
          when msg_token == token do
        import Helen.Time.Helper, only: [utc_now: 0]

        pos_rc = adjust_switch(cmd, dev_name)

        send_at_timer_msg_if_needed(msg, :at_finish, dev_name)

        Map.merge(s, %{switch_rc: pos_rc, active_cmd: :none})
        |> noreply()
      end

      # NOTE:  when the msg_token does not match the state token then
      #        a change has occurred and this off message should be ignored
      def handle_info({:timer, _msg, _msg_token}, s) do
        noreply(s)
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

      def adjust_switch(cmd, name) do
        case cmd do
          :on -> Switch.on(name)
          :off -> Switch.off(name)
        end
      end

      def send_at_timer_msg_if_needed(
            {cmd, cmd_opts, reply_pid} = _original_cmd_msg,
            category,
            dev_name
          ) do
        # if the matching ':at' option was specified
        for {c, at_opts} when c == category <- cmd_opts,
            # examine the at opts for :notify
            opt when opt == :notify <- at_opts do
          msg = {:gen_device, category, cmd, dev_name}

          IO.puts(["sending ", inspect(reply_pid), " ", inspect(msg)])
          send(reply_pid, msg)
        end
      end

      defp schedule_timer_if_needed(
             %{token: token} = s,
             reply_pid,
             {cmd, cmd_opts}
           ) do
        import Helen.Time.Helper, only: [list_to_ms: 2]
        import Process, only: [send_after: 3]

        case cmd_opts[:for] do
          nil ->
            nil

          x ->
            send_after(
              self(),
              {:timer, {cmd, cmd_opts, reply_pid}, token},
              list_to_ms(x, [])
            )
        end

        reply(:ok, s)
      end

      defp update_state(state, :switch_rc, sw_rc) do
        import Helen.Time.Helper, only: [utc_now: 0]

        state
        |> Map.merge(%{cached_value: sw_rc, last_device_change: utc_now()})
      end

      # empty opts list is always valid
      defp valid_on_off_opts([]), do: true

      defp valid_on_off_opts?(opts) do
        import Helen.Time.Helper, only: [valid_duration_opts?: 1]

        for opt <- opts do
          case opt do
            {:for, x} -> valid_duration_opts?(x)
            {:at_start, [:notify]} -> true
            {:at_finish, [:notify]} -> true
            _x -> false
          end
        end
        |> Enum.all?(fn x -> x == true end)
      end

      ##
      ## State Helpers
      ##

      defp loop_timeout(%{opts: opts}) do
        import TimeSupport, only: [list_to_ms: 2]

        list_to_ms(opts[:timeout], seconds: 30)
      end

      defp state_merge(%{} = s, %{} = map), do: Map.merge(s, map)

      defp update_last_timeout(s) do
        import TimeSupport, only: [utc_now: 0]

        put_in(s, [:last_timeout], utc_now())
        |> Map.update(:timeouts, 1, &(&1 + 1))
      end

      ##
      ## handle_* return helpers
      ##

      defp noreply(s), do: {:noreply, s, loop_timeout(s)}
      defp noreply_merge_state(s, map), do: {:noreply, Map.merge(s, map)}
      defp reply(val, s), do: {:reply, val, s, loop_timeout(s)}
    end
  end
end