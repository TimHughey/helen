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
          active_cmd: nil,
          device_name: c_opts[:device_name],
          device_adjusts: 0,
          last: %{
            timeout: epoch(),
            cmd: nil,
            pid: nil,
            adjust_at: epoch(),
            device_rc: nil,
            value_rc: nil
          },
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

      @doc """
      Return a map of the device name managed by this GenDevice and the module
      manading the device.

      Useful for creating a map of known "devices" when working with many
      GenDevice managed devices.

      Returns a map.

      ## Examples

          iex> GenDevice.device_module_map
          %{"device name" => __MODULE__}

      """
      @doc since: "0.0.27"
      def device_module_map, do: Map.put(%{}, state(:device_name), __MODULE__)

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
      Set the device managed by this server to off.

      See `GenDevice.on/1` for options.

      Returns :ok or an error tuple

      ## Examples

          iex> GenDevice.off()
          :ok

      """
      @doc since: "0.0.27"
      def off(opts \\ []) when is_list(opts) do
        GenServer.call(__MODULE__, {:off, List.flatten(opts)})
      end

      @doc """
      Set the device managed by this server to on.

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
        GenServer.call(__MODULE__, {:on, List.flatten(opts)})
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
      def handle_call({:mode, mode}, _from, state) do
        case mode do
          # the GenDevice is being made ready for commands when set :active,
          # don't adjust the device
          :active ->
            put_in(state, [:standby_reason], :none)

          # when going to :standby ensure the device is off
          :standby ->
            put_in(state, [:standby_reason], :api_call)
            |> adjust_device(:off)
        end
        |> put_in([:mode], mode)
        |> reply({:ok, mode})
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
      def handle_call({:value, opts}, _from, %{device_name: dev_name} = s) do
        import Switch, only: [position: 1]

        case opts do
          [:cached] ->
            reply(s, s[:last][:value_rc])

          [] ->
            pos_rc = position(dev_name)

            s
            |> put_in([:last, :value_rc], pos_rc)
            |> reply(pos_rc)

          opts ->
            reply(s, {:bad_args, opts})
        end
      end

      @doc false
      @impl true
      def handle_call({cmd, _cmd_opts} = msg, {pid, _ref}, %{} = state) do
        state
        # if requested in the cmd opts send a msg the cmd is starting
        # the timer msg ultimately becomes the original msg with the caller's
        # pid appended
        |> send_at_timer_msg_if_needed(msg, pid, :at_start)
        # increment the token to invalidate pending timers
        |> update_in([:token], fn x -> x + 1 end)
        |> adjust_device(cmd)
        |> put_in([:active_cmd], cmd)
        |> put_in([:last, :pid], pid)
        |> schedule_timer_if_needed_and_reply(pid, msg)
      end

      @doc false
      @impl true
      def handle_continue(:bootstrap, %{device_name: dev_name} = state) do
        import Switch, only: [position: 1, exists?: 1]

        # if the device does not exist immediately entry standby mode
        # and note the reason
        case exists?(dev_name) do
          true ->
            state
            |> put_in([:last, :value_rc], position(dev_name))
            |> noreply()

          false ->
            state
            |> put_in([:mode], :standby)
            |> put_in([:standby_reason], :device_does_not_exist)
            |> noreply()
        end
      end

      @doc false
      @impl true
      # handle the case when the msg_token matches the current state.
      def handle_info({:timer, msg, msg_token}, %{token: token} = state)
          when msg_token == token do
        state
        |> send_at_timer_msg_if_needed(msg, :at_finish)
        |> adjust_device_if_needed([])
        |> put_in([:active_cmd], :none)
        |> noreply()
      end

      # NOTE:  when the msg_token does not match the state token then
      #        a change has occurred so ignore this timer message
      def handle_info({:timer, _msg, _msg_token}, s) do
        noreply(s)
      end

      @doc false
      @impl true
      def handle_info(:timeout, s) do
        update_last_timeout(s)
        |> timeout_hook()
      end

      ##
      ## GenServer Receive Loop Hooks
      ##

      defp timeout_hook(%{} = state) do
        noreply(state)
      end

      ##
      ## PRIVATE
      ##

      defp adjust_device(%{device_name: dev_name} = state, cmd) do
        import Helen.Time.Helper, only: [utc_now: 0]

        dev_rc =
          case cmd do
            :on -> Switch.on(dev_name)
            cmd when cmd in [:off, :standby] -> Switch.off(dev_name)
          end

        state
        |> put_in([:last, :device_rc], dev_rc)
        |> put_in([:last, :cmd], cmd)
        |> put_in([:last, :adjust_at], utc_now())
        |> update_in([:device_adjusts], fn x -> x + 1 end)
      end

      defp adjust_device_if_needed(%{} = state, opts) do
        # if there was an :at_cmd_finish opt specified and it's either :on or
        # :off then adjust the switch.
        case opts[:at_cmd_finish] do
          nil -> state
          cmd when cmd in [:on, :off] -> adjust_device(state, cmd)
        end
      end

      defp call_if_valid_opts(msg, cmd_opts) do
        case valid_on_off_opts?(cmd_opts) do
          true -> GenServer.call(__MODULE__, msg)
          false -> {:bad_args, cmd_opts}
        end
      end

      # helper so the same function name can be used for both :at_start and :at_end
      # this function matches the call from :at_start
      defp send_at_timer_msg_if_needed(
             state,
             {_cmd, _cmd_opts} = msg,
             pid,
             category
           )
           when is_pid(pid) do
        send_at_timer_msg_if_needed(state, Tuple.append(msg, pid), category)
      end

      # this function matches the call from :at_end
      defp send_at_timer_msg_if_needed(
             state,
             # orignal cmd message
             {cmd, cmd_opts, reply_pid},
             category
           ) do
        # if the matching ':at' option was specified
        for {:notify, notify_opts} <- cmd_opts,
            at_opt when at_opt == category <- notify_opts do
          msg = {:gen_device, {category, cmd, __MODULE__}}

          send(reply_pid, msg)
        end

        state
      end

      defp schedule_timer_if_needed_and_reply(
             %{token: token} = s,
             reply_pid,
             {_cmd, cmd_opts} = msg
           ) do
        import Helen.Time.Helper, only: [to_ms: 1]
        import Process, only: [send_after: 3]

        case cmd_opts[:for] do
          nil ->
            nil

          x ->
            timer_msg = Tuple.append(msg, reply_pid)
            send_after(self(), {:timer, timer_msg, token}, to_ms(x))
        end

        reply(:ok, s)
      end

      # empty opts list is always valid
      defp valid_on_off_opts([]), do: true

      defp valid_on_off_opts?(opts) do
        import Helen.Time.Helper, only: [valid_ms?: 1]

        # we reduce the list down to a boolean that represents if all
        # the opts are valid (true) or invalid (false)
        for opt <- opts, reduce: true do
          # this is either the beginning of the reduction of true or
          # we've only seen valid opts.  check the current opt.
          true ->
            case opt do
              # for: x must be a valid duration
              {:for, x} ->
                valid_ms?(x)

              # notify: should be a list and each opt must be either
              # :at_start or :at_finish.  here we reduce the list to a
              # boolean representing if all items in the list are valid.
              {:notify, notify_opts} when is_list(notify_opts) ->
                for o <- notify_opts, reduce: true do
                  true -> o in [:at_start, :at_finish]
                  false -> false
                end

              # at_cmd_finish: should be an atom that represents what
              # final command to execute when this command is finished
              {:at_cmd_finish, cmd} when is_atom(cmd) ->
                true

              # none of the above matched, this isn't a valid opt
              _x ->
                false
            end

          # we've already seen an invalid opt, no need to check this opt
          false ->
            false
        end
      end

      ##
      ## State Helpers
      ##

      defp loop_timeout(%{opts: opts}) do
        import Helen.Time.Helper, only: [to_ms: 2]

        to_ms(opts[:timeout], "PT30.0S")
      end

      defp state_merge(%{} = s, %{} = map), do: Map.merge(s, map)

      defp update_last_timeout(state) do
        import TimeSupport, only: [utc_now: 0]

        state
        |> put_in([:last, :timeout], utc_now())
        |> Map.update(:timeouts, 1, &(&1 + 1))
      end

      ##
      ## GenServer handle_* return helpers
      ##

      defp noreply(s), do: {:noreply, s, loop_timeout(s)}
      defp reply(s, val) when is_map(s), do: {:reply, val, s, loop_timeout(s)}
      defp reply(val, s) when is_map(s), do: {:reply, val, s, loop_timeout(s)}
    end
  end
end
