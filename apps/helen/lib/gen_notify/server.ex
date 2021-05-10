defmodule GenNotify do
  @moduledoc """
    GenNotify allows modules to receive notifications for Switch, Sensor and
    PulseWidth inbound messages.
  """

  @type msg() :: %{device: {:ok, Ecto.Schema.t()}} | %{device: {term(), term()}}

  @callback extract_dev_alias_from_msg(msg()) :: map()

  defmacro __using__(use_opts) do
    quote location: :keep, bind_quoted: [use_opts: use_opts] do
      @behaviour GenNotify

      use GenServer, shutdown: 2000

      def extract_dev_alias_from_msg(%{device: {:ok, %_{aliases: aliases}}}), do: aliases

      def extract_dev_alias_from_msg(msg), do: []
      defoverridable extract_dev_alias_from_msg: 1

      @doc false
      @impl true
      def init(args), do: GenNotify.init(args)

      @doc false
      def start_link(opts), do: GenNotify.start_link(__MODULE__, opts)

      ##
      ## Public API
      ##

      def alive?, do: GenNotify.alive?(__MODULE__)

      def notify_as_needed(msg) do
        # call the user defined function to extract the device alias(es)
        # that will be used for notifications
        dev_alias = extract_dev_alias_from_msg(msg)

        GenNotify.notify_as_needed(msg, dev_alias, __MODULE__)
      end

      @doc """
      Register the caller's pid to receive notifications when the named sensor
      is updated by handle_message

      Required opts:  [name: "device", notify_interval: [minutes: 1]]
      """
      @doc since: "0.0.26"
      def notify_register(opts) when is_list(opts),
        do: GenNotify.notify_register(opts, __MODULE__)

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
      def restart(opts \\ []), do: GenNotify.restart(opts, __MODULE__)

      ##
      ## GenServer handle_* callbacks
      ##

      @doc false
      @impl true
      def handle_call(what, from, s), do: GenNotify.handle_call(what, from, s)

      @doc false
      @impl true
      def handle_cast(what, s), do: GenNotify.handle_cast(what, s)
    end
  end

  require Logger

  #
  # GenNotify Implementation
  #

  def alive?(mod) do
    if GenServer.whereis(mod), do: true, else: false
  end

  def init(args) do
    %{opts: args, notify_map: %{}} |> reply_ok()
  end

  def handle_call(:state, _from, s), do: reply(s, s)

  def handle_call({:notify_register, requester, interval}, {pid, _ref}, s) do
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
    registration_details = %{opts: [interval: interval], last: DateTime.from_unix!(0)}

    # add the requestors identifier to the notify map
    notify_map = Map.put_new(s.notify_map, requester, %{})

    %{s | notify_map: put_in(notify_map, [requester, pid], registration_details)} |> reply(:ok)
  end

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

            new_pid_map = Map.put(r_pid_map, pid_key, %{opts: o, last: utc_now()})

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
    end
    |> noreply()
  end

  def notify_all(aliases, mod) do
    aliases = List.wrap(aliases) |> List.flatten()

    for %_{name: name} = x <- aliases do
      GenServer.cast(mod, {:notify, x})
      name
    end
  end

  # NOTE:  notify_as_needed/3 is designed to be used in a pipeline so the
  # original msg is always returned

  # (1 of zzz) we have a list of aliases
  def notify_as_needed(msg, aliases, mod) when is_list(aliases) do
    put_in(msg, [:notifies], notify_all(aliases, mod))
  end

  # (1 of 3) opts are a list. provide defaults for missing args and convert to map
  def notify_register(opts, mod) when is_list(opts) do
    # defaults
    [link: true, notify_interval: "PT1S"]
    |> Keyword.merge(opts)
    |> notify_register(opts[:name], mod)
  end

  # (2 of 3) opts contains the minimum required args
  def notify_register(opts, name, mod) when is_binary(name) do
    register = fn -> GenServer.call(mod, {:notify_register, name, opts[:notify_interval]}) end

    # 1. GenServer is local (has a pid) then register and link by default
    # 2. GenServer is local and link explictly set to false
    # 3. GenServer not alive
    # 4. GenServer is remote, link not possible
    case {GenServer.whereis(mod), Keyword.take(opts, [:link])} do
      {pid, [link: true]} when is_pid(pid) -> {register.(), Process.link(pid) && :linked}
      {pid, [link: false]} when is_pid(pid) -> {register.(), :nolink}
      {nil, _} -> {:no_server, mod}
      {_remote, _unable_to_link} -> {register.(), :nolink}
    end
  end

  # (3 of 3) missing :name or something else
  def notify_register(_, _name, _mod), do: {:bad_args, usage: [name: "name", notify_interval: "PT1S"]}

  def restart(opts \\ [], mod) do
    # the Supervisor is the base of the module name with Supervisor appended
    [sup_base | _tail] = Module.split(mod)

    sup_mod = Module.concat([sup_base, "Supervisor"])

    if GenServer.whereis(mod) do
      Supervisor.terminate_child(sup_mod, mod)
    end

    Supervisor.delete_child(sup_mod, mod)
    Supervisor.start_child(sup_mod, {mod, opts})
  end

  def start_link(mod, opts) do
    Logger.debug(["starting ", inspect(mod)])
    GenServer.start_link(mod, opts, name: mod)
  end

  defp noreply(s), do: {:noreply, s}
  defp reply(s, val) when is_map(s), do: {:reply, val, s}
  defp reply(val, s), do: {:reply, val, s}
  defp reply_ok(s), do: {:ok, s}
end
