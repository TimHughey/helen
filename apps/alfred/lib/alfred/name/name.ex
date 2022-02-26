defmodule Alfred.Name do
  @moduledoc """
  Abstract Name Server Instance
  """

  require Logger
  use GenServer

  @registry Alfred.Name.Supervisor.registry()

  defstruct name: nil, nature: nil, seen_at: nil, ttl_ms: 30_000, module: nil, callbacks: %{}

  @type t :: %__MODULE__{
          name: String.t(),
          nature: :cmds | :datapoints,
          seen_at: DateTime.t(),
          ttl_ms: pos_integer(),
          module: module(),
          callbacks: %{:status => any(), :execute => any()}
        }

  @type action :: :execute | :status
  @type name_action_callback :: {action, pid} | {action, module}
  @type to_register :: any()

  # Behaviour
  @callback register(map, list) :: map
  @callback unregister(map) :: map

  @doc since: "0.3.0"
  def allowed_opts, do: Map.from_struct(__MODULE__) |> Map.keys()

  def available?(name), do: not registered?(name)

  def info(<<_::binary>> = name), do: call({:info}, name)

  @invoke_pre_checks [:found?, :ttl_check, :invoke, :finalize]
  def invoke(%{name: name} = args, action) do
    name_info = info(name)
    args = update_in(args, [:ref_dt], &Kernel.if(&1, do: &1, else: Timex.now()))

    Enum.reduce_while(@invoke_pre_checks, name_info, fn
      :found?, {:not_found, name} -> not_found(name, action)
      :found?, info -> {:cont, info}
      :ttl_check, info -> ttl_check(info, args, action)
      :invoke, info -> {:cont, Alfred.Name.Callback.invoke(info, args, action)}
      :finalize, result -> {:halt, result}
    end)
  end

  def missing?(any, opts) when is_list(opts) do
    case any do
      <<_::binary>> = name -> call({:missing?, opts}, name)
      %{name: name} -> call({:missing?, opts}, name)
      _ -> {:failed, :bad_args}
    end
  end

  @doc since: "0.3.0"
  def registered?(<<_::binary>> = name) do
    case info(name) do
      %{name: ^name} -> true
      _ -> false
    end
  end

  @doc since: "0.3.1"
  def registered do
    Registry.select(@registry, [{{:"$1", :_, :_}, [], [:"$1"]}]) |> Enum.sort()
  end

  def seen_at(%{name: name}), do: seen_at(name)

  # (2 of 2)
  def seen_at(name) when is_binary(name), do: call({:get, :seen_at}, name)

  @doc false
  def not_found(name, action) do
    case action do
      :execute -> {:halt, Alfred.Execute.not_found(name)}
      :status -> {:halt, Alfred.Status.not_found(name)}
    end
  end

  @doc since: "0.4.2"
  def register(%{name: _, register: _, seen_at: _} = item, module, opts) do
    case Enum.into(opts, %{}) do
      %{register: false} -> Map.put(item, :register, :skipped)
      %{register: opts} when is_list(opts) -> register_now(item, module, opts)
      _ -> register_now(item, module, [])
    end
  end

  @allowed " allowed opts "
  def register(item, module, _opts) do
    [inspect(module), @allowed, inspect(allowed_opts()), "\n", inspect(item, pretty: true)]
    |> IO.iodata_to_binary()
    |> raise()
  end

  @doc false
  @steps [:name_map, :opts, :callbacks, :update, :finalize]
  def register_now(%{name: _, register: _} = original, module, opts) do
    use_opts = get_use_opts(module, opts)

    callbacks =
      case use_opts[:backend] do
        :module -> %{execute_cmd: {module, 2}, status_lookup: {module, 2}}
        :message -> %{execute_cmd: self(), status_lookup: self()}
      end

    opts = Keyword.put(opts, :module, module)

    Enum.reduce(@steps, original, fn
      :name_map, %{} = raw -> Map.drop(raw, [:__struct__])
      :opts, %{} = name_map -> Map.merge(name_map, Enum.into(opts, %{}))
      :callbacks, name_map -> Map.put(name_map, :callbacks, callbacks)
      :update, name_map -> update_or_register(name_map, opts)
      :finalize, %{register: register} -> Map.put(original, :register, register)
    end)
  end

  @doc false
  @ttl_error_tags [module: __MODULE__, ttl_expired: true, rc: :ttl_expired]
  def ttl_check(%{ttl_ms: ttl_ms, seen_at: at} = info, opts, action) do
    ref_dt = get_in(opts, [:ref_dt])
    ttl_ms = get_in(opts, [:ttl_ms]) || ttl_ms

    ttl_start_at = Timex.shift(ref_dt, milliseconds: ttl_ms * -1)

    if Timex.before?(ttl_start_at, at) do
      {:cont, info}
    else
      ms = Timex.diff(ref_dt, at, :millisecond)
      fields = [name: info.name, rc: {:ttl_expired, ms}]

      {:ok, _map} = Betty.app_error([{:name, info.name} | @ttl_error_tags])

      case action do
        :execute -> {:halt, struct(Alfred.Execute, fields)}
        :status -> {:halt, struct(Alfred.Status, fields)}
      end
    end
  end

  def unregister(name) when is_binary(name) do
    case Registry.lookup(@registry, name) do
      [{pid, _}] -> GenServer.stop(pid, :normal)
      [] -> :ok
    end
  end

  @doc false
  def update_or_register(%{name: name} = register_map, opts) do
    server = server(name)
    GenServer.call(server, {:update, register_map, opts})
  catch
    _kind, {:noproc, _} ->
      start_args = Map.put(register_map, :from, self())
      start_opts = [name: server(name), restart: :temporary]

      {:ok, pid} = GenServer.start_link(__MODULE__, start_args, start_opts)

      Map.put(register_map, :register, pid)

    kind, reason ->
      ["\n", inspect(register_map, pretty: true), "\n", Exception.format(kind, reason, __STACKTRACE__)]
      |> IO.iodata_to_binary()
      |> raise()
  end

  ## GenServer

  @impl true
  def init(%{} = fields) do
    Process.link(fields.from)

    {:ok, struct(__MODULE__, fields)}
  end

  @impl true
  def handle_call({:get, key}, _from, state) when is_map_key(state, key) do
    Map.get(state, key) |> reply(state)
  end

  @impl true
  def handle_call({:info}, _from, state) do
    Map.from_struct(state) |> reply(state)
  end

  @impl true
  def handle_call({:missing?, opts}, _from, state) do
    at = opts[:ref_dt] || Timex.now()
    ttl_ms = opts[:ttl_ms] || state.ttl_ms

    diff_greater_than_ms?(at, state.seen_at, ttl_ms)
    |> reply(state)
  end

  @impl true
  def handle_call({:update, %{} = item, opts}, _from, state) do
    :ok = Alfred.Notify.dispatch(state, opts)

    # NOTE: accept seen_at AND ttl_ms as updates
    # NOTE: the registered name can never change it's nature, callbacks or name
    Map.take(item, [:seen_at, :ttl_ms])
    |> then(fn fields -> struct(state, fields) end)
    |> reply(item)
  end

  @impl true
  def handle_call(msg, _from, state), do: {:invalid_msg, msg} |> reply(state)

  @impl true
  @doc false
  def terminate(reason, %{name: name} = state) do
    reason = inspect(reason)
    pid = inspect(self())
    ["\n", "  ", name, " ", pid, " terminating ", reason] |> Logger.debug()

    state
  end

  @doc false
  def diff_greater_than_ms?(lhs, rhs, ms), do: Timex.diff(lhs, rhs, :milliseconds) >= ms

  @doc false
  def server(name), do: {:via, Registry, {@registry, name}}

  defp call(msg, name) do
    server(name) |> GenServer.call(msg)
  catch
    _kind, {:noproc, {GenServer, :call, _}} ->
      {:not_found, name}

    kind, reason ->
      ["\n", Exception.format(kind, reason, __STACKTRACE__)] |> Logger.warn()

      {:failed, {kind, reason}}
  end

  defp reply(rc, %__MODULE__{} = state), do: {:reply, rc, state}
  defp reply(%__MODULE__{} = state, rc), do: {:reply, rc, state}

  # coveralls-ignore-start

  @doc false
  defmacro __using__(use_opts) do
    quote bind_quoted: [use_opts: use_opts] do
      # NOTE: capture use opts for Alfred.Name
      Alfred.Name.put_attribute(__MODULE__, use_opts)

      @behaviour Alfred.Name
      def register(item, opts \\ []) do
        case item do
          [%{name: _} | _] = items -> Enum.map(items, &register(&1, opts))
          %{name: _} -> Alfred.Name.register(item, __MODULE__, opts)
          _ -> []
        end
      end

      def unregister(%{name: _} = item) do
        case item do
          [%{name: _} | _] = items -> Enum.map(items, &unregister(&1))
          %{name: name} -> Alfred.Name.unregister(name)
          <<_::binary>> = name -> Alfred.Name.unregister(name)
        end
      end
    end
  end

  @mod_attribute :alfred_name_use_opts

  @doc false
  def get_use_opts(module, opts) do
    attributes = module.__info__(:attributes)

    use_opts = get_in(attributes, [@mod_attribute, :use_opts]) || []

    Keyword.merge(use_opts, opts)
  end

  @doc false
  def put_attribute(module, use_opts) do
    unless Keyword.get(use_opts, :backend) do
      raise("use opts must specify :backend (:module | :message)")
    end

    Module.register_attribute(module, @mod_attribute, persist: true)
    Module.put_attribute(module, @mod_attribute, use_opts: use_opts)
  end

  # coveralls-ignore-stop
end
