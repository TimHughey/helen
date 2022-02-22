defmodule Sally.Dispatch do
  require Logger
  use GenServer

  alias Sally.Types, as: Types

  @callback child_spec(Types.child_spec_opts()) :: Supervisor.child_spec()
  @callback process(struct()) :: struct()
  @callback post_process(struct()) :: struct()
  @optional_callbacks [post_process: 1]

  defstruct subsystem: nil,
            category: nil,
            ident: nil,
            filter_extra: [],
            payload: nil,
            data: nil,
            halt_reason: :none,
            module: nil,
            sent_at: nil,
            recv_at: nil,
            log: [],
            routed: :no,
            host: :not_loaded,
            txn_info: :none,
            final_at: nil,
            opts: []

  @type host_ident() :: String.t()
  @type subsystem() :: String.t()
  @type category() :: String.t()
  @type extras() :: [] | [String.t(), ...]
  @type payload() :: bitstring()

  @type t :: %__MODULE__{
          subsystem: subsystem(),
          category: category(),
          ident: host_ident(),
          filter_extra: extras(),
          payload: payload(),
          data: map() | nil,
          halt_reason: :none | String.t(),
          module: nil | module(),
          sent_at: DateTime.t() | nil,
          recv_at: DateTime.t() | nil,
          log: list(),
          routed: :no | :ok,
          host: Ecto.Schema.t() | nil,
          txn_info: :none | {:ok, map()} | {:error, map()},
          final_at: DateTime.t() | nil,
          opts: [] | [{:echo, boolean()}]
        }

  defmacro __using__(use_opts) do
    quote bind_quoted: [use_opts: use_opts] do
      subsystem = Keyword.get(use_opts, :subsystem)
      unless subsystem, do: raise("use opts must specify subsystem")

      Sally.Dispatch.attribute(:put, {__MODULE__, use_opts})
      @behaviour Sally.Dispatch

      @doc false
      @impl true
      def child_spec(_) do
        use_opts = Sally.Dispatch.attribute(:get, __MODULE__)
        subsystem = use_opts[:subsystem]

        # NOTE: we use a Registry for routing Dispatch(es) to the correct handlers
        start_args = {Sally.Dispatch.server(subsystem), {__MODULE__, use_opts}}

        %{id: __MODULE__, start: {Sally.Dispatch, :start_link, [start_args]}}
      end
    end
  end

  @mod_attribute :sally_dispatch_use_opts

  @doc false
  def attribute(what, opts \\ []) do
    case opts do
      module when is_atom(module) and what == :get ->
        module.__info__(:attributes) |> Keyword.get(@mod_attribute, [])

      {module, [_ | _] = opts} when is_atom(module) and what == :put ->
        Module.register_attribute(module, @mod_attribute, persist: true)
        Module.put_attribute(module, @mod_attribute, opts)
    end
  end

  @impl true
  def init({module, use_opts}) do
    state = %{module: module, opts: use_opts}

    {:ok, state}
  end

  def start_link({name, args}) do
    GenServer.start_link(__MODULE__, args, name: name)
  end

  @doc false
  @registry Sally.Dispatch.Supervisor.registry()
  def server(%Sally.Dispatch{} = dispatch), do: dispatch.subsystem |> server()
  def server(<<_::binary>> = subsystem), do: {:via, Registry, {@registry, subsystem}}

  @impl true
  def handle_call(%__MODULE__{} = dispatch, {caller_pid, _ref}, state) do
    # NOTE: reply quickly to free up MQTT handler, do the heavy lifting in the server
    dispatch = update(dispatch, routed: :ok)
    {:reply, dispatch, state, {:continue, {dispatch, caller_pid}}}
  end

  @impl true
  @tags [:module, :subsytem]
  def handle_continue({dispatch, caller_pid}, state) do
    dispatch = reduce(dispatch, state.module)

    if dispatch.opts[:echo] == "dispatch", do: Process.send(caller_pid, dispatch, [])

    hostname = if match?(%{host: %{name: _}}, dispatch), do: dispatch.host.name, else: "unknown"

    tags = Map.take(dispatch, @tags) |> Map.put(:host, hostname)
    fields = %{processed_us: Timex.diff(dispatch.final_at, dispatch.sent_at, :microseconds)}
    {:ok, _point} = Betty.runtime_metric(tags, fields)

    {:noreply, state}
  end

  @doc since: "0.7.10"
  @filter_levels [:ident, :subsystem, :category, :filter_extra]
  def accept([_ | _] = filter, payload) when is_bitstring(payload) do
    dispatch = new(payload: payload, recv_at: Timex.now())

    # NOTE: reduce the filter level list into the appropriate dispatch struct fields
    Enum.reduce(@filter_levels, {dispatch, filter}, fn
      # NOTE: filter_extra collects all remaining filter levels and provides the
      # completed Dispatch as the final accumulator
      :filter_extra, {d, levels_extra} -> update(d, filter_extra: levels_extra)
      field, {d, [level | levels_rest]} -> {update(d, [{field, level}]), levels_rest}
    end)
    # NOTE: dispatch is sent to subsystem server
    # NOTE: dispatch is returned with routed: :ok or with halt_reason set
    |> handoff()
  end

  @handoff_error "handoff failure"
  # NOTE: executes within the caller (aka Sally.Mqtt.Handler)
  @doc false
  def handoff(%__MODULE__{} = dispatch) do
    server = server(dispatch)

    try do
      GenServer.call(server, dispatch)
    catch
      _, _ -> halt([@handoff_error, inspect(server)], dispatch)
    end
    |> finalize()
  end

  @doc false
  @steps [:load_host, :unpack, :mtime, :prune_data, :filter_check, :process, :post_process, :finalize, :log]
  def reduce(%__MODULE__{} = dispatch, module) do
    dispatch = update(dispatch, module: module)

    # NOTE: each step function returns the dispatch
    Enum.reduce(@steps, dispatch, fn
      :log, %{halt_reason: <<_::binary>>} = dispatch -> tap(dispatch, &Logger.warn(&1.halt_reason))
      :log, dispatch -> dispatch
      :finalize, dispatch -> finalize(dispatch)
      # NOTE: prevent remaining steps from executing when halt_reason is set
      _step, %{halt_reason: <<_::binary>>} = dispatch -> dispatch
      step, dispatch -> apply(__MODULE__, step, [dispatch])
    end)
  end

  ## Process step functions

  def finalize(dispatch), do: [final_at: Timex.now()] |> update(dispatch)

  @subsystems ["immut", "mut"]
  def filter_check(%{subsystem: sub, filter_extra: filter_extra} = dispatch) do
    case {sub, filter_extra} do
      {sub, [ident, "error" = status]} when sub in @subsystems -> halt([sub, ident, status], dispatch)
      {sub, [_ident, "ok"]} when sub in @subsystems -> dispatch
      {"host", _} -> dispatch
      {"mut", [_refid]} -> dispatch
      {sub, [ident, status]} -> halt([sub, ident, status], dispatch)
    end
  end

  @host_categories ["startup", "boot", "run", "ota", "log"]
  @host_cat_err "unknown host category"
  @sub_cat_err "unknown subsystem/category"
  @no_auth "host not authorized"
  @unknown_host "unknown host"
  @doc false
  def load_host(%{category: cat, ident: host_ident, subsystem: sub} = dispatch) do
    case {sub, cat} do
      {"host", cat} when cat in @host_categories ->
        dispatch

      {sub, _cat} when sub in @subsystems ->
        host = Sally.Host.find_by(ident: host_ident)

        case host do
          %{authorized: true} -> [host: host] |> update(dispatch)
          %{authorized: false} -> [@no_auth, host_ident] |> halt(dispatch)
          nil -> [@unknown_host, host_ident] |> halt(dispatch)
        end

      {"host", cat} ->
        [@host_cat_err, cat] |> halt(dispatch)

      {sub, cat} ->
        [@sub_cat_err, sub, cat] |> halt(dispatch)
    end
  end

  @mtime_err "mtime is missing"
  @future_err "data is from the future"
  @stale_err "data is stale"
  @variance_opt [Sally.Dispatch.Handler, :mtime_variance_ms]
  @variance_ms Application.compile_env(:sally, @variance_opt, 10_000)
  @unit_ms :millisecond
  @doc false
  def mtime(%{data: data, recv_at: recv_at} = dispatch) do
    mtime = data[:mtime]
    sent_at = if(mtime, do: DateTime.from_unix!(mtime, @unit_ms), else: nil)
    ms_diff = if(sent_at, do: DateTime.diff(recv_at, sent_at, @unit_ms), else: nil)

    cond do
      is_nil(sent_at) -> halt(@mtime_err, dispatch)
      ms_diff < @variance_ms * -1 -> halt([@future_err, "#{ms_diff * -1}ms"], dispatch)
      ms_diff >= @variance_ms -> halt([@stale_err, "#{ms_diff}ms"], dispatch)
      true -> [sent_at: sent_at] |> update(dispatch)
    end
  end

  @doc false
  def process(%{module: module} = dispatch) do
    txn_info = module.process(dispatch)

    case txn_info do
      {:ok, %{host: host}} -> [host: host, txn_info: %{}]
      {:ok, txn_info} -> [txn_info: txn_info]
    end
    |> update(dispatch)
  end

  @doc false
  @post_process_path [:_post_process_]
  def post_process(%{module: module, txn_info: txn_info} = dispatch) do
    arity = module.__info__(:functions) |> get_in([:post_process])

    case arity do
      1 -> [txn_info: put_in(txn_info, @post_process_path, module.post_process(dispatch))]
      _ -> [txn_info: put_in(txn_info, @post_process_path, :none)]
    end
    |> update(dispatch)
  end

  @doc false
  @data_prune [:mtime, :log, :echo]
  def prune_data(%{data: data, log: log, opts: opts} = dispatch) do
    [
      # NOTE: prune consumed data keys
      data: Map.drop(data, @data_prune),
      log: Keyword.put(log, :log, Map.get(data, :log, false)),
      opts: Keyword.put(opts, :echo, Map.get(data, :echo, false))
    ]
    |> update(dispatch)
  end

  @payload_error "payload unpack failure"
  @doc false
  def unpack(%{payload: payload} = dispatch) do
    data = Msgpax.unpack!(payload) |> atomize_keys()
    update(dispatch, data: data, payload: :unpacked)
  catch
    _, _ -> halt(@payload_error, dispatch)
  end

  ## Helpers
  @doc false
  def atomize_keys(x) when is_map(x) do
    # NOTE: only atomize base map keys
    Enum.into(x, %{}, fn
      {<<_::binary>> = key, val} -> {String.to_atom(key), val}
      kv -> kv
    end)
  end

  @doc false
  def halt(reason, %__MODULE__{} = dispatch) do
    case reason do
      <<_::binary>> -> reason
      [<<_::binary>> | _] -> Enum.join(reason, " ")
    end
    |> then(fn reason -> struct(dispatch, halt_reason: reason) end)
  end

  def halt([<<_::binary>> | _] = parts, %__MODULE__{} = dispatch) do
    Enum.join(parts, " ") |> halt(dispatch)
  end

  def new(fields), do: struct(__MODULE__, fields)

  @doc false

  def update(arg1, arg2) do
    case {arg1, arg2} do
      {[_ | _] = fields, %__MODULE__{} = dispatch} -> struct(dispatch, fields)
      {%__MODULE__{} = dispatch, [_ | _] = fields} -> struct(dispatch, fields)
      _ -> raise("bad update args")
    end
  end
end
