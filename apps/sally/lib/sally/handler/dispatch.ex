defmodule Sally.Dispatch do
  require Logger
  use GenServer

  alias Sally.Types, as: Types

  @callback child_spec(Types.child_spec_opts()) :: Supervisor.child_spec()
  @callback process(struct()) :: struct()
  @callback process_many(any(), struct()) :: {:ok, map()} | {:error, map()}
  @callback post_process(struct()) :: struct()
  @optional_callbacks [process_many: 2, post_process: 1]

  # @derive {Inspect, only: [:valid?, :subsystem, :category]}
  defstruct env: nil,
            subsystem: nil,
            category: nil,
            post_process?: false,
            ident: nil,
            filter_extra: [],
            payload: nil,
            data: nil,
            halt_reason: :none,
            callback_mod: nil,
            sent_at: nil,
            recv_at: nil,
            log: [],
            routed: :no,
            host: :not_loaded,
            txn_info: :none,
            final_at: nil,
            valid?: false,
            invalid_reason: "not processed",
            opts: []

  @type env() :: String.t()
  @type host_ident() :: String.t()
  @type subsystem() :: String.t()
  @type category() :: String.t()
  @type extras() :: [] | [String.t(), ...]
  @type payload() :: bitstring()

  @type t :: %__MODULE__{
          env: env(),
          subsystem: subsystem(),
          category: category(),
          post_process?: boolean(),
          ident: host_ident(),
          filter_extra: extras(),
          payload: payload(),
          data: map() | nil,
          halt_reason: :none | String.t(),
          callback_mod: nil | module(),
          sent_at: DateTime.t() | nil,
          recv_at: DateTime.t() | nil,
          log: list(),
          routed: :no | :ok,
          host: Ecto.Schema.t() | nil,
          txn_info: :none | {:ok, map()} | {:error, map()},
          final_at: DateTime.t() | nil,
          valid?: boolean(),
          invalid_reason: String.t(),
          opts: [] | [{:echo, boolean()}]
        }

  defmacro __using__(use_opts) do
    quote bind_quoted: [use_opts: use_opts] do
      subsystem = Keyword.get(use_opts, :subsystem, :none)
      if subsystem == :none, do: raise("must include subsystem: String.t() in use opts")

      Sally.Dispatch.attribute(:put, {__MODULE__, use_opts})
      @behaviour Sally.Dispatch

      @doc false
      @impl true
      def child_spec(_) do
        use_opts = Sally.Dispatch.attribute(:get, __MODULE__)
        subsystem = Keyword.get(use_opts, :subsystem)
        state = Enum.into(use_opts, %{callback_mod: __MODULE__})

        # NOTE: we use a Registry for routing Dispatch(es) to the correct handlers
        name = Sally.Dispatch.server(subsystem)
        start_args = {name, state}

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
  def init(%{} = opts), do: {:ok, _state = %{opts: opts}}

  def start_link({name, state}) do
    GenServer.start_link(__MODULE__, state, name: name)
  end

  @doc false
  @registry Sally.Dispatch.Supervisor.registry()
  def server(%Sally.Dispatch{} = dispatch), do: dispatch.subsystem |> server()
  def server(<<_::binary>> = subsystem), do: {:via, Registry, {@registry, subsystem}}

  @doc false
  def call(msg, mod) when is_tuple(msg) and is_atom(mod) do
    case GenServer.whereis(mod) do
      x when is_pid(x) -> GenServer.call(x, msg)
      _ -> {:no_server, mod}
    end
  end

  @doc false
  def cast(msg, mod) when is_tuple(msg) and is_atom(mod) do
    # returns:
    # 1. {:ok, original msg}
    # 2. {:no_server, original_msg}
    case GenServer.whereis(mod) do
      x when is_pid(x) -> {GenServer.cast(x, msg), msg}
      _ -> {:no_server, mod}
    end
  end

  @impl true
  def handle_call(%__MODULE__{} = dispatch, {caller_pid, _ref}, state) do
    # NOTE: reply quickly to free up MQTT handler, do the heavy lifting in the server
    {:reply, :ok, state, {:continue, {dispatch, caller_pid}}}
  end

  @impl true
  def handle_cast(%__MODULE__{} = dispatch, state) do
    %{opts: %{callback_mod: callback_mod}} = state

    # NOTE: return value ignored, pure side effects function
    _ = reduce(dispatch, callback_mod)

    {:noreply, state}
  end

  @impl true
  def handle_continue({%{opts: opts} = dispatch, caller_pid}, state) do
    %{opts: %{callback_mod: callback_mod}} = state

    dispatch = reduce(dispatch, callback_mod)

    if opts[:echo] == "dispatch", do: Process.send(caller_pid, dispatch, [])

    {:noreply, state}
  end

  ##
  ## Private
  ##

  @doc """
  Accepts a topic filter parts and payload to create a `%Dispatch{}`

  ## Topic Filter Parts
  ```
  [
    env,        # "test", "prod"
    ident,      # host identifier
    subsystem,  # "host", "pwm", "i2c", "ds"
    category,   # "boot", "run", "ota", "log", "mut", "imm"
    extras,     # list of topic specific additional binarys
    payload,    # MsgPack bitstring of topic specific data
  ]

  ```
  """
  @doc since: "0.5.10"
  @type topic_parts() :: [String.t(), ...]
  @type accept_tuple() :: {topic_parts(), payload()}
  @spec accept(accept_tuple()) :: Sally.Dispatch.t()
  def accept({[env, ident, subsystem, category, extras], payload}) do
    [
      env: env,
      subsystem: subsystem,
      category: category,
      ident: ident,
      filter_extra: extras,
      payload: payload
    ]
    |> then(fn fields -> struct(__MODULE__, fields) end)
  end

  def check_txn(%Sally.Dispatch{} = dispatch) do
    case dispatch do
      # NOTE: filter out invalid Dispatch to avoid matching on valid? below
      %{valid?: false} -> dispatch
      %{txn_info: {:ok, %{host: host}}} -> valid([host: host, txn_info: :host], dispatch)
      %{txn_info: {:ok, txn_info}} -> valid([txn_info: txn_info], dispatch)
      %{txn_info: {:error, _multi_key, txn_error, _detail}} -> invalid(dispatch, txn_error)
      %{txn_info: :none} -> dispatch
    end
    |> update(dispatch)
  end

  def finalize(dispatch) do
    [final_at: DateTime.utc_now()]
    |> update(dispatch)
    |> tap(fn dispatch -> log_if_invalid(dispatch) end)
  end

  def halt_reason(<<_::binary>> = reason, %Sally.Dispatch{} = dispatch) do
    [halt_reason: reason] |> update(dispatch)
  end

  def handoff(%Sally.Dispatch{} = dispatch), do: route_now(dispatch)

  def invalid(%Sally.Dispatch{} = dispatch, fields) when is_list(fields) do
    Keyword.put(fields, :valid?, false) |> update(dispatch)
  end

  def invalid(%Sally.Dispatch{} = dispatch, reason, fields) when is_list(fields) do
    fields = Keyword.put(fields, :invalid_reason, invalid_reason(reason))

    invalid(dispatch, fields)
  end

  def invalid_reason(reason) do
    case reason do
      <<_::binary>> -> [invalid_reason: reason]
      _ -> [invalid_reason: inspect(reason, pretty: true)]
    end
  end

  @not_authorized "host not authorized"
  @unknown_host "unknown host"
  def load_host(%Sally.Dispatch{valid?: true, ident: host_ident} = dispatch) do
    case Sally.Host.find_by_ident(host_ident) do
      %Sally.Host{authorized: true} = host -> [host: host] |> valid(dispatch)
      %Sally.Host{authorized: false} = host -> invalid(dispatch, @not_authorized, host: host)
      nil -> invalid(dispatch, @unknown_host)
    end
  end

  def load_host(%{valid?: false} = dispatch), do: dispatch

  def new(fields), do: struct(Sally.Dispatch, fields)

  @data_prune [:mtime, :log, :echo]
  def preprocess(%Sally.Dispatch{log: log, opts: opts} = dispatch) do
    with %{valid?: true} = dispatch <- check_metadata(dispatch),
         %{valid?: true, data: data} = dispatch <- unpack(dispatch),
         %{valid?: true} = dispatch <- check_sent_time(dispatch) do
      # NOTE: ensure data is a map
      data = data || %{}

      [
        # NOTE: prune consumed data keys
        data: Map.drop(data, @data_prune),
        log: Keyword.put(log, :log, Map.get(data, :log, false)),
        opts: Keyword.put(opts, :echo, Map.get(data, :echo, false))
      ]
      |> update(dispatch)
    else
      dispatch -> dispatch
    end
  end

  def process(%Sally.Dispatch{category: "status", filter_extra: [_ident, "error"]} = dispatch) do
    halt_reason("host reported status error", dispatch)
  end

  def process(%Sally.Dispatch{callback_mod: callback_mod} = dispatch) do
    # NOTE: support process/1 returning either a database result tuple _OR_ a map
    # when we get a map merge it into the existing txn_info

    callback_mod.process(dispatch)
    |> save_txn_info(dispatch)
  end

  # def process_many(dispatch) do
  #   %{callback_mod: mod, category: category, txn_info: txn_info} = dispatch
  #
  #   manys = attribute(mod) |> Keyword.get(:process_many, [])
  #   category = String.to_atom(category)
  #
  #   if function_exported?(mod, :process_many, 1) do
  #     Enum.reduce(manys, txn_info, fn
  #       {^category, txn_key}, txn_info when is_map_key(txn_info, txn_key) ->
  #         many = Map.get(txn_info, txn_key)
  #
  #         # NOTE process_many/2 returns a {key, val} pair to add to txn_info
  #         # and returns the updated txn_info as the accumulator
  #         Enum.into(many, txn_info, fn item -> mod.process_many(item, dispatch) end)
  #
  #       # NOTE: category doesn't match or key doesn't exist in txn_info
  #       _, txn_info ->
  #         txn_info
  #     end)
  #     # NOTE: updated txn_info is the result of the reduction, store the latest
  #     |> then(fn txn_info -> [txn_info: txn_info] |> update(dispatch) end)
  #   else
  #     dispatch
  #   end
  # end

  def post_process(%{callback_mod: callback_mod, post_process?: true} = dispatch) do
    callback_mod.post_process(dispatch)
    |> valid(:_post_process_, dispatch)
  end

  def post_process(%{} = dispatch), do: valid(:none, :_post_process_, dispatch)

  @order [:routed, :process, :check_txn, :post_process, :finalize, :finished]
  def reduce(%Sally.Dispatch{} = dispatch, callback_mod) do
    Enum.reduce_while(@order, dispatch, fn
      _function, %{valid?: false} = dispatch -> {:halt, Sally.Dispatch.finalize(dispatch)}
      _function, %{halt_reason: <<_::binary>>} -> {:halt, Sally.Dispatch.finalize(dispatch)}
      :finished, dispatch -> {:halt, dispatch}
      :routed, dispatch -> {:cont, Sally.Dispatch.routed(dispatch, callback_mod)}
      function, dispatch -> {:cont, apply(Sally.Dispatch, function, [dispatch])}
    end)
  end

  def route_now(%{} = dispatch) do
    update(dispatch, routed: :ok)
    |> tap(fn dispatch -> GenServer.call(server(dispatch), dispatch) end)
  end

  def routed(dispatch, callback_mod) when is_atom(callback_mod) do
    exported? = function_exported?(callback_mod, :post_process, 1)

    [callback_mod: callback_mod, post_process?: exported?]
    |> update(dispatch)
  end

  def routed(%{} = dispatch, _), do: dispatch |> finalize()

  def save_txn_info(txn_info, %{} = dispatch) do
    [txn_info: txn_info] |> update(dispatch)
  end

  def unpack(%{payload: payload} = dispatch) do
    valid(dispatch, data: Msgpax.unpack!(payload) |> atomize_keys(), payload: :unpacked)
  catch
    _, _ -> invalid(dispatch, "payload is not a bitstring")
  end

  def update(%Sally.Dispatch{} = dispatch), do: dispatch

  def update(fields, %Sally.Dispatch{} = dispatch) when is_list(fields) do
    struct(dispatch, fields)
  end

  def update(%Sally.Dispatch{} = new, %Sally.Dispatch{} = _old), do: new

  def update(%Sally.Dispatch{} = dispatch, fields) when is_list(fields) do
    update(fields, dispatch)
  end

  def valid(%Sally.Dispatch{} = dispatch) do
    [valid?: true, invalid_reason: :none] |> update(dispatch)
  end

  def valid(fields, %Sally.Dispatch{} = dispatch) when is_list(fields) do
    fields |> update(dispatch) |> valid()
  end

  def valid(%Sally.Dispatch{} = dispatch, fields) when is_list(fields) do
    Keyword.merge(fields, valid?: true, invalid_reason: :none)
    |> update(dispatch)
  end

  def valid(val, key, %Sally.Dispatch{txn_info: txn_info} = dispatch) when is_atom(key) do
    txn_info = if(is_map(txn_info), do: txn_info, else: %{})
    [txn_info: Map.put(txn_info, key, val)] |> valid(dispatch)
  end

  # only atomze base map keys
  defp atomize_keys(x) when is_map(x) do
    for {k, v} <- x, into: %{} do
      if is_binary(k), do: {String.to_atom(k), v}, else: {k, v}
    end
  end

  @host_categories ["startup", "boot", "run", "ota", "log"]
  @subsystems ["immut", "mut"]
  defp check_metadata(%{} = m) do
    case {m.subsystem, m.category} do
      {"host", cat} when cat in @host_categories -> valid(m)
      {subsystem, _cat} when subsystem in @subsystems -> valid(m) |> load_host()
      x -> invalid(m, "unknown subsystem/category: #{inspect(x)}")
    end
  end

  @variance_opt [Sally.Dispatch.Handler, :mtime_variance_ms]
  @variance_ms Application.compile_env(:sally, @variance_opt, 10_000)
  defp check_sent_time(%{data: data} = m) do
    recv_at = m.recv_at || DateTime.utc_now()
    sent_at = DateTime.from_unix!(data[:mtime] || 0, :millisecond)

    m = update(m, recv_at: recv_at, sent_at: sent_at)
    ms_diff = DateTime.diff(recv_at, sent_at, :millisecond)

    cond do
      DateTime.compare(sent_at, DateTime.from_unix!(0)) == :eq -> invalid(m, "mtime is missing")
      ms_diff < @variance_ms * -1 -> invalid(m, "data is from the future #{ms_diff * -1}ms")
      ms_diff < 0 -> m
      ms_diff >= @variance_ms -> invalid(m, "data is #{ms_diff} old")
      true -> m
    end
  end

  defp log_if_invalid(%{valid?: true} = dispatch), do: dispatch

  defp log_if_invalid(%{valid?: false, invalid_reason: invalid_reason}) do
    case invalid_reason do
      <<_::binary>> -> [invalid_reason]
      _ -> ["\n", inspect(invalid_reason, pretty: true)]
    end
    |> tap(fn log -> Logger.warn(log) end)
  end
end
