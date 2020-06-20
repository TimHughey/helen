defmodule Switch.Server do
  @moduledoc """
    Switch GenServer Implementation
  """

  use Timex
  use GenServer, shutdown: 7000

  use Helen.Module.Config

  alias Switch.DB.Device, as: Device
  alias Switch.DB.Alias, as: Alias

  ##
  ## GenServer Start and Initialization
  ##

  @doc false
  @impl true
  def init(args) do
    import TimeSupport, only: [now: 0]

    state =
      %{last_timeout: now(), opts: config_opts(args), notify_map: %{}}
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

  @doc """
  Sends notifications to registered pids using the message passed.

  This is function is called by device's handle_message/1
  """
  @doc since: "0.0.26"
  def notify_as_needed(msg) do
    with {:ok, %Device{aliases: aliases}} <- msg[:device],
         true <- is_list(aliases) and aliases != [] do
      GenServer.cast(__MODULE__, {:notify, aliases})
      msg
    else
      _no_match -> msg
    end
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
      GenServer.call(__MODULE__, {:notify_register, name, interval})
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
  def restart do
    Supervisor.terminate_child(Switch.Supervisor, __MODULE__)
    Supervisor.restart_child(Switch.Supervisor, __MODULE__)
  end

  ##
  ## GenServer handle_* callbacks
  ##

  @doc false
  @impl true
  def handle_call(:state, _from, s), do: reply(s, s)

  @doc false
  @impl true
  def handle_call({:notify_register, x, interval}, {pid, _ref}, s) do
    import TimeSupport, only: [epoch: 0]

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

    # create the opts that will be used for this device notification
    opts = [interval: interval]

    # NOTE: adding a new notification pid must be done in two steps
    #       because the device may not exist in the notification map

    # ensure there is a map for this device so we can use put_in to update
    new_notify_map = Map.put_new(s[:notify_map], x, %{})
    state = Map.put(s, :notify_map, new_notify_map)

    # put the pid map into :notify_map -> device -> pid
    state = put_in(state[:notify_map][x][pid], %{opts: opts, last: epoch()})

    reply(:ok, state)
  end

  @doc false
  @impl true
  def handle_cast({:notify, seen_list}, %{notify_map: _notify_map} = s) do
    import TimeSupport, only: [expired?: 3, utc_now: 0]
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
        %Alias{name: n} = item when n == registered_name <-
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
        should_notify? = expired?(l, :interval, o)

        cond do
          alive? and should_notify? ->
            # the pid is alive and the notify interval has elapsed
            send(pid_key, {:notify, :switch, item})

            new_pid_map =
              Map.put(r_pid_map, pid_key, %{opts: o, last: utc_now()})

            new_notify_map = Map.put(r_notify_map, registered_name, new_pid_map)

            # update the state (accumulator)
            Map.put(state, :notify_map, new_notify_map)

          alive? == false ->
            # this pid is dead, remove it from the notify map
            new_pid_map = Map.drop(r_pid_map, [pid_key])

            new_notify_map = Map.put(r_notify_map, registered_name, new_pid_map)

            # update the state (accumulator)
            Map.put(state, :notify_map, new_notify_map)

          true ->
            # nothing to do, simply return the state (accumulator)
            state
        end

        # |> (fn x ->
        #       ["new state: ", inspect(x, pretty: true)] |> IO.puts()
        #       x
        #     end).()
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
    import TimeSupport, only: [now: 0]

    state = Map.update(s, :loops, 1, &(&1 + 1)) |> Map.put(:last_timeout, now())

    loop_hook(state)
  end

  ##
  ## PRIVATE
  ##

  defp loop_hook(%{} = s) do
    noreply(s)
  end

  defp loop_put_timeout(%{opts: opts} = s) do
    import TimeSupport, only: [opts_as_ms: 1]

    ms = (opts[:loop_timeout] || [minutes: 1]) |> opts_as_ms()

    Map.put(s, :loop_timeout_ms, ms)
  end

  defp loop_timeout(%{loop_timeout_ms: ms}), do: ms

  defp noreply(s), do: {:noreply, s, loop_timeout(s)}
  defp reply(val, s), do: {:reply, val, s, loop_timeout(s)}
end
