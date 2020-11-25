defmodule GenNotify do
  @moduledoc """
    GenNotify allows modules to receive notifications for Switch, Sensor and
    PulseWidth inbound messages.
  """

  @type msg :: %{device: {:ok, Ecto.Schema.t()}} | %{device: {term, term}}

  @callback extract_dev_alias_from_msg(msg) :: map()

  defmacro __using__(use_opts) do
    quote location: :keep, bind_quoted: [use_opts: use_opts] do
      @behaviour GenNotify

      use GenServer, restart: :transient, shutdown: 5000

      @doc false
      @impl true
      def init(args) do
        import Helen.Time.Helper, only: [utc_now: 0]

        state =
          %{last_timeout: utc_now(), opts: args, notify_map: %{}}
          |> loop_put_timeout()

        {:ok, state, 100}
      end

      @doc false
      def start_link(opts) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      ##
      ## Public API
      ##

      def notify_as_needed(msg) do
        # call the user defined function to extract the device alias(es)
        # that will be used for notifications
        case extract_dev_alias_from_msg(msg) do
          [] ->
            nil

          # single device alias
          %_{name: _} = x ->
            GenServer.cast(__MODULE__, {:notify, x})

          # list of aliases
          list_of_aliases when is_list(list_of_aliases) ->
            for %_{name: _} = x <- list_of_aliases do
              GenServer.cast(__MODULE__, {:notify, x})
            end

          _no_match ->
            nil
        end

        # always pass through the original message
        msg
      end

      @doc """
      Register the caller's pid to receive notifications when the named sensor
      is updated by handle_message

      Required opts:  [name: "device", notify_interval: [minutes: 1]]
      """
      @doc since: "0.0.26"
      def notify_register(opts) when is_list(opts) do
        with name when is_binary(name) <- opts[:name],
             interval when is_list(opts) <- opts[:notify_interval] do
          import Process, only: [monitor: 1]

          rc = GenServer.call(__MODULE__, {:notify_register, name, interval})

          {rc, monitor(__MODULE__)}
        else
          _bad_opts ->
            {:bad_args, usage: [name: "name", notify_interval: [minutes: 1]]}
        end
      end

      @doc """
      Retrieves the notification map for diagnostic use.
      """
      @doc since: "0.0.27"
      def notify_map do
        GenServer.call(__MODULE__, :state)[:notify_map]
      end

      @doc """
      Retrieves the current state of the GenServer for diagnostic use.
      """
      @doc since: "0.0.26"
      def state, do: GenServer.call(__MODULE__, :state)

      @doc """
      Restarts the server.
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

      ##
      ## GenServer handle_* callbacks
      ##

      @doc false
      @impl true
      def handle_call(:state, _from, s), do: reply(s, s)

      @doc false
      @impl true
      def handle_call({:notify_register, x, interval}, {pid, _ref}, state) do
        import Helen.Time.Helper, only: [epoch: 0]

        # NOTE:  shape of s (state) relevant for this function
        #
        # s = %{
        #   notify_map: %{
        #     "name" => %{"pid1" => %{opts: o, last: l}},
        #     "name2" => %{
        #       "pid1" => %{opts: o, last: l},
        #       "pid2" => %{opts: o, last: l}
        #     }
        #   }
        # }

        # info for this registeration
        registration_details = %{opts: [inteval: interval], last: epoch()}

        state
        |> update_in([:notify_map, x], fn
          # create a new map containing only this pid
          nil -> %{pid => registration_details}
          # there is already a registration for this name, add this new one
          %{} = map -> Map.put(map, pid, registration_details)
        end)
        |> reply(:ok)
      end

      @doc false
      @impl true
      def handle_cast({:notify, seen_list}, %{notify_map: _notify_map} = s) do
        import Helen.Time.Helper, only: [expired?: 2, utc_now: 0]
        import List, only: [flatten: 1]

        # NOTE:  shape of s (state) relevant for this function
        #
        # s = %{
        #   notify_map: %{
        #     "name" => %{"pid1" => %{opts: o, last: l}},
        #     "name2" => %{
        #       "pid1" => %{opts: o, last: l},
        #       "pid2" => %{opts: o, last: l}
        #     }
        #   }
        # }

        # use the notify_map as the first generator to minimize unfolding since
        # we act only on registered notification pids

        # NOTE
        #  this assumes the notify map has less keys then the unique devices
        #  receiving updates
        for {registered_name, pid_map} <- s[:notify_map] || %{},
            # unfold the pid map
            {pid_key, %{opts: o, last: l}} <- pid_map,
            # unfold the seen_list filtering by registered name
            # ensure we're dealing with a list, wrap and flatten seen_list
            %_{name: n} = item when n == registered_name <-
              flatten([seen_list]),
            # we now have all what we need to send a message to a registered pid
            # finally, we'll be reducing the original state
            reduce: s do
          #
          # NOTE:
          #  a. using reduce: requires the -> syntax (like with, case, cond)
          #  b. since we are updating the notify_map we need to grab it each pass
          #
          %{notify_map: r_notify_map} = state ->
            # now grab the latest pid_map
            r_pid_map = r_notify_map[registered_name]

            # grab some additional items for final checks before notifying
            alive? = Process.alive?(pid_key)
            should_notify? = expired?(l, o[:interval] || "PT1M")

            cond do
              alive? and should_notify? ->
                # the pid is alive and the notify interval has elapsed

                # create the category atom that is sent as part of the notify msg
                # the category atom is the the current module's first level
                # downcased
                [base | _tail] = Module.split(__MODULE__)
                category = String.downcase(base) |> String.to_atom()

                # send the msg
                send(pid_key, {:notify, category, item})

                new_pid_map =
                  Map.put(r_pid_map, pid_key, %{opts: o, last: utc_now()})

                new_notify_map =
                  Map.put(r_notify_map, registered_name, new_pid_map)

                # update the state (accumulator)
                Map.put(state, :notify_map, new_notify_map)

              alive? == false ->
                # this pid is dead, remove it from the notify map
                new_pid_map = Map.drop(r_pid_map, [pid_key])

                new_notify_map =
                  Map.put(r_notify_map, registered_name, new_pid_map)

                # update the state (accumulator)
                Map.put(state, :notify_map, new_notify_map)

              true ->
                # nothing to do, simply return the state (accumulator)
                state
            end
        end
        |> noreply()
      end

      @doc false
      @impl true
      def handle_continue(:bootstrap, s) do
        noreply(s)
      end

      @doc false
      @impl true
      def handle_info(:timeout, s) do
        import Helen.Time.Helper, only: [utc_now: 0]

        state =
          Map.update(s, :loops, 1, &(&1 + 1))
          |> Map.put(:last_timeout, utc_now())

        loop_hook(state)
      end

      ##
      ## PRIVATE
      ##

      defp loop_hook(%{} = s) do
        noreply(s)
      end

      defp loop_put_timeout(%{opts: opts} = s) do
        import Helen.Time.Helper, only: [to_ms: 1]

        ms = (opts[:loop_timeout] || "PT1M") |> to_ms()

        Map.put(s, :loop_timeout_ms, ms)
      end

      defp loop_timeout(%{loop_timeout_ms: ms}), do: ms

      defp noreply(s), do: {:noreply, s, loop_timeout(s)}
      defp reply(s, val) when is_map(s), do: {:reply, val, s, loop_timeout(s)}
      defp reply(val, s), do: {:reply, val, s, loop_timeout(s)}

      @before_compile GenNotify
      @after_compile GenNotify
    end
  end

  def __after_compile__(%{aliases: _aliases} = _env, _bytecode) do
    # IO.puts(inspect(env, pretty: true))
  end

  defmacro __before_compile__(%{aliases: _aliases} = _env) do
    # IO.puts(inspect(env, pretty: true))
  end
end
