defmodule Alfred.Notify do
  require Logger
  use GenServer

  @registry Alfred.Notify.Supervisor.registry()

  defstruct name: nil,
            ref: nil,
            pid: nil,
            missing_timer: nil,
            at: %{missing: nil, seen: :never, notified: :never},
            opts: %{ms: %{interval: 60_000, missing: 60_000}, send_missing_msg: false}

  @doc since: "0.3.0"
  def allowed_opts, do: [:interval_ms, :missing_ms, :send_missing_msg]

  def dispatch(%{name: name_binary} = name, opts) when is_list(opts) do
    Registry.dispatch(@registry, name_binary, fn entries ->
      for {notifier_pid, {_caller_pid, _ref}} <- entries do
        GenServer.cast(notifier_pid, {:notify, name, opts})
      end
    end)
  end

  @doc since: "0.3.0"
  def find_registration(<<_::binary>> = name, caller_pid) when is_pid(caller_pid) do
    guards = [{:==, :"$1", name}]

    registrations(guards)
    |> Enum.filter(fn {_name, _notifier_pid, {pid, _ref}} -> pid == caller_pid end)
    # NOTE: unwrap the result as we're guaranteed a single result when found; [] == not found
    |> List.first([])
  end

  def find_registration(want_ref) when is_reference(want_ref) do
    # NOTE: assigning variables here for clarity; Registry is new and requires atypical syntax
    caller_pid = self()

    # NOTE: guard compare tuples must be wrapped in a tuple!
    guards = [{:==, :"$3", {{caller_pid, want_ref}}}]

    registrations(guards)
    # NOTE: unwrap the result as we're guaranteed a single result when found; [] == not found
    |> List.first([])
  end

  @doc since: "0.3.0"
  def register([_ | _] = opts) do
    {names, opts_rest} = Keyword.split(opts, [:name, :equipment])

    case names do
      [{_key, <<_::binary>> = name}] -> register(name, opts_rest)
      [_ | _] = multiple -> raise(ArgumentError, "ambiguous name: #{inspect(multiple)}")
      _ -> raise(ArgumentError, "name missing from opts")
    end
  end

  def register(<<_::binary>> = name, opts) when is_list(opts) do
    # NOTE: this code runs under the caller process therefore will return the
    # notify registration for this name if it existws
    caller_pid = self()

    case find_registration(name, caller_pid) do
      [] -> start_notifier(name, opts)
      {_name, notifier_pid, {_caller_pid, _ref}} -> call({:get, :ticket}, notifier_pid)
    end
  end

  def register(%{equipment: equipment, ticket: ticket} = map, opts) do
    case ticket do
      %Alfred.Ticket{} -> map
      _ -> Map.put(map, :ticket, register(equipment, opts))
    end
  end

  @doc since: "0.3.0"
  def registrations(guards \\ []) when is_list(guards) do
    # NOTE: assigning variables here for clarity; Registry is new and requires atypical syntax
    fields = {:"$1", :"$2", :"$3"}

    # NOTE: we use tuples for efficient match / compare when calling Regitry.select/2
    #  1. shape of stored value: {name, notifier_pid, {caller_pid, ref}}
    #  2. must wrap the desired shape tuple in a tuple!
    shape = {{:"$1", :"$2", :"$3"}}

    Registry.select(@registry, [{fields, guards, [shape]}])
  end

  @doc since: "0.3.0"
  def seen_at(ref) when is_reference(ref) do
    case find_registration(ref) do
      {_name, notifier_pid, {_caller_pid, _ref}} -> call({:get, [:at, :seen]}, notifier_pid)
      _ -> {:failed, {:unknown_ref, ref}}
    end
  end

  @doc since: "0.3.0"
  # def unregister(%Alfred.Ticket{ref: ref}), do: unregister(ref)

  def unregister(ref) when is_reference(ref) do
    case find_registration(ref) do
      {_name, notifier_pid, {_caller_pid, _ref}} -> call({:unregister, ref}, notifier_pid)
      _ -> :ok
    end
  end

  def unregister(%{} = map) do
    case map do
      %Alfred.Ticket{ref: ref} ->
        unregister(ref)

      %{ticket: {:ok, %Alfred.Ticket{} = ticket}} ->
        _ = unregister(ticket)
        Map.put(map, :ticket, :none)

      _ ->
        map
    end
  end

  # GENSERVER
  # GENSERVER
  # GENSERVER

  @impl true
  def init(args) do
    caller_pid = Keyword.get(args, :link_pid)

    Process.link(caller_pid)

    state = make_state(args)
    reg_key = state.name
    reg_val = {caller_pid, state.ref}

    {:ok, _owner_pid} = Registry.register(@registry, reg_key, reg_val)

    {:ok, state}
  end

  @impl true
  def handle_call({:get, path}, _from, state) do
    map = Map.from_struct(state)

    case path do
      :ticket -> {:ok, Alfred.Ticket.new(map)}
      [key | _] when is_atom(key) -> get_in(map, path) || {:bad_path, path}
      _ -> {:bad_path, path}
    end
    |> reply(state)
  end

  @impl true
  # NOTE: duplicate variables in the pattern are matched
  def handle_call({:unregister, ref}, _from, %{ref: ref} = state) do
    # :normal exit won't restart the linked process because we're a temporary process

    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_call(msg, from, state) do
    msg = inspect(msg, pretty: true)
    from = inspect(from)
    state_binary = inspect(state, pretty: true)

    ["unmatched call msg\n  from: ", from, "\n  msg: ", msg, "\n\n", state_binary]
    |> Logger.warn()

    reply(:error, state)
  end

  @impl true
  def handle_cast({:notify, %{seen_at: seen_at}, _opts}, state) do
    state
    |> missing_timer()
    |> update_at(:seen, seen_at)
    |> notify()
    |> noreply()
  end

  @impl true
  def handle_cast(msg, state) do
    msg = inspect(msg, pretty: true)
    state_binary = inspect(state, pretty: true)

    ["unmatched cast\n  msg: ", msg, "\n\n", state_binary]
    |> Logger.debug()

    noreply(state)
  end

  @impl true
  def handle_info(:missing, state) do
    {:ok, _map} = missing_log(state)
    :ok = missing_send_if_needed(state)

    update_at(state, :missing, now())
    |> missing_timer()
    |> noreply()
  end

  @impl true
  def handle_info(msg, state) do
    msg = inspect(msg, pretty: true)
    state_binary = inspect(state, pretty: true)

    ["unmatched info\n  msg:", msg, "\n\n", state_binary]
    |> Logger.debug()

    noreply(state)
  end

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  @doc false
  defmacro format_exception(kind, reason) do
    quote do
      ["\n", Exception.format(unquote(kind), unquote(reason), __STACKTRACE__)] |> Logger.warn()

      {:failed, {unquote(kind), unquote(reason)}}
    end
  end

  @doc false
  @catch_values [:noproc, :normal]
  def call(msg, pid) do
    GenServer.call(pid, msg)
  catch
    _kind, {val, {GenServer, _, _}} when val in @catch_values -> {:no_server, pid}
    kind, reason -> format_exception(kind, reason)
  end

  defmacro put_ms(key, val) do
    quote bind_quoted: [key: key, val: val], do: put_in(var!(acc), [:ms, key], val)
  end

  defmacro put_opt(key, val) do
    quote bind_quoted: [key: key, val: val], do: put_in(var!(acc), [key], val)
  end

  @doc false
  def make_state(opts) do
    {name, opts_rest} = Keyword.pop(opts, :name)
    {pid, opts_rest} = Keyword.pop(opts_rest, :link_pid)

    fields = [name: name, pid: pid, ref: make_ref()]
    state = struct(__MODULE__, fields) |> update_at(:missing, now())

    opts_map =
      Enum.reduce(opts_rest, state.opts, fn
        {:interval_ms, :all = val}, acc -> put_ms(:interval, val)
        {:interval_ms, x}, acc when is_integer(x) -> put_ms(:interval, x)
        {:missing_ms, x}, acc when x < 100 -> put_ms(:missing, 100)
        {:missing_ms, x}, acc when is_integer(x) -> put_ms(:missing, x)
        {:send_missing_msg, x}, acc when is_boolean(x) -> put_opt(:send_missing_msg, x)
        _kv, acc -> acc
      end)

    struct(state, opts: opts_map) |> missing_timer()
  end

  @doc false
  @missing_tags [module: __MODULE__, missing: true]
  def missing_log(%{name: name}) do
    Betty.app_error([{:name, name} | @missing_tags])
  end

  @doc false
  def missing_send_if_needed(%{opts: opts} = state) do
    case opts do
      %{send_missing_msg: true} -> Alfred.Memo.send(state, missing?: true)
      _ -> :ok
    end
  end

  @missing :missing
  @cancel_opts [async: true, info: false]
  @doc false
  def missing_timer(%{missing_timer: timer} = state) do
    is_reference(timer) && Process.cancel_timer(timer, @cancel_opts)

    missing_ms = get_in(state.opts, [:ms, @missing])

    struct(state, missing_timer: Process.send_after(self(), @missing, missing_ms))
  end

  @doc false
  def now, do: Timex.now()

  @doc false
  def notify(%{at: at_map, opts: opts} = state) do
    notified = get_in(at_map, [:notified])
    ms = get_in(opts, [:ms, :interval])

    cond do
      ms == :all -> true
      is_integer(ms) and since_ms(notified) >= ms -> true
      true -> false
    end
    |> tap(fn send? -> send? && Alfred.Memo.send(state, []) end)

    update_at(state, :notified, now())
  end

  # def notify_now(true = _send?, state), do: tap(state, &Alfred.Memo.send(&1, []))
  # def notify_now(false = _send?, state), do: state

  @doc false
  def since_ms(last_at) do
    last_at = if(last_at == :never, do: Timex.from_unix(0), else: last_at)

    Timex.diff(now(), last_at)
  end

  @doc false
  def start_notifier(name, opts) do
    args = Keyword.merge(opts, name: name, link_pid: self(), restart: :temporary)

    {:ok, notifier_pid} = GenServer.start_link(__MODULE__, args)

    call({:get, :ticket}, notifier_pid)
  end

  # @doc false
  # @timeout_types [:only_ms, :ensure_timeout]
  # def timeout_ms(state, type) when type in @timeout_types do
  #   last_missing_at = state.at.missing
  #   missing_ms = state.opts.ms.missing
  #
  #   elapsed_ms = Timex.diff(now(), last_missing_at, :milliseconds)
  #
  #   cond do
  #     elapsed_ms > missing_ms and type == :ensure_timeout -> {:continue, :missing}
  #     elapsed_ms > missing_ms -> 0
  #     true -> missing_ms - elapsed_ms
  #   end
  # end

  @doc false
  def update_at(%{at: at_map} = state, key, %DateTime{} = at) do
    struct(state, at: Map.put(at_map, key, at))
  end

  @doc false
  def noreply(state), do: {:noreply, state}

  @doc false
  def reply(rc, %__MODULE__{} = state), do: {:reply, rc, state}
end
