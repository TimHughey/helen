defmodule Alfred.Broom do
  @moduledoc false

  require Logger
  use GenServer

  @registry Alfred.Broom.Supervisor.registry()

  @timeout_ms_default 3300

  defstruct refid: nil,
            tracked_info: nil,
            at: %{sent: nil, tracked: nil, released: nil, timeout: nil},
            rc: :none,
            module: nil,
            notify_pid: nil,
            timeout_ms: @timeout_ms_default,
            opts: []

  @type at_map :: %{
          :sent => DateTime.t(),
          :tracked => DateTime.t(),
          :released => DateTime.t(),
          :timeout => DateTime.t()
        }

  @type t :: %__MODULE__{
          refid: String.t(),
          tracked_info: map() | struct(),
          rc: :none | :ok | :timeout,
          at: at_map(),
          module: module(),
          notify_pid: :none | pid(),
          timeout_ms: pos_integer(),
          opts: list()
        }

  @callback broom_timeout(Alfred.Broom.t()) :: any()
  @callback make_refid() :: String.t()
  @callback now() :: DateTime.t()
  @callback release(refid :: String.t(), opts :: list()) :: :ok
  @callback track(schema :: map(), opts :: list()) :: Broom.t()
  @callback tracked_info(refid :: String.t()) :: any()

  # coveralls-ignore-start
  defmacro __using__(use_opts) do
    quote bind_quoted: [use_opts: use_opts] do
      # NOTE: capture use opts for Alfred.Broom
      Alfred.Broom.put_attribute(__MODULE__, use_opts)
      @behaviour Alfred.Broom

      def make_refid, do: Alfred.Broom.make_refid()

      @doc false
      def now(), do: Alfred.Broom.now()

      def release(refid, opts), do: Alfred.Broom.release(refid, __MODULE__, opts)

      def track(exec_result, opts), do: Alfred.Broom.track(exec_result, __MODULE__, opts)

      def tracked_info(refid), do: Alfred.Broom.tracked_info(refid, __MODULE__)
    end
  end

  @mod_attribute :alfred_broom_use_opts

  @doc false
  def put_attribute(module, use_opts) do
    Module.register_attribute(module, @mod_attribute, persist: true)
    Module.put_attribute(module, @mod_attribute, use_opts)
  end

  # coveralls-ignore-stop

  @doc false
  def get_attribute(module) do
    attributes = module.__info__(:attributes)

    Keyword.get(attributes, @mod_attribute, [])
  end

  @doc false
  defdelegate use_opts(module), to: __MODULE__, as: :get_attribute

  def make_refid do
    UUID.uuid4() |> String.split("-") |> List.first()
  end

  def release(refid, module, opts) do
    {:release, refid, opts_final(module, opts)} |> call(refid)
  end

  def track(%{refid: refid} = exec_result, module, opts) do
    [tracked_info: exec_result, module: module, opts: opts_final(module, opts), caller_pid: self()]
    |> then(fn args -> GenServer.start_link(__MODULE__, args, name: server(refid)) end)
  end

  def tracked?(refid) do
    case Registry.lookup(@registry, refid) do
      [{pid, _}] when is_pid(pid) -> true
      _ -> false
    end
  end

  def tracked_info(refid, module) do
    {:tracked_info, refid, opts_final(module, [])} |> call(refid)
  end

  ## GenServer

  @doc false
  def child_spec(args) do
    {restart, args_rest} = Keyword.pop(args, :restart, :temporary)
    caller_pid = Keyword.get(args, :caller_pid)
    refid = Keyword.get(args, :tracked_info) |> Map.get(:refid)

    %{id: {refid, caller_pid}, start: {__MODULE__, :start_link, [args_rest]}, restart: restart}
  end

  @impl true
  def init(opts) do
    {caller_pid, opts_rest} = Keyword.pop(opts, :caller_pid)

    Process.link(caller_pid)
    state = make_state(caller_pid, opts_rest)

    :ok = Alfred.Broom.Metrics.count(state)

    {:ok, state, timeout_ms(state)}
  end

  @doc false
  def make_state(caller_pid, opts) do
    {fields_base, opts_rest} = Keyword.split(opts, [:tracked_info, :module])
    opts_actual = Keyword.get(opts_rest, :opts, [])

    {tracked_at, opts_clean} = Keyword.pop(opts_actual, :ref_dt, now())

    tracked_info = Keyword.get(fields_base, :tracked_info)

    [
      refid: tracked_info.refid,
      notify_pid: notify?(opts_clean) && caller_pid,
      timeout_ms: opt(opts_clean, :timeout_ms),
      opts: opts_clean
    ]
    |> then(fn fields -> struct(__MODULE__, fields ++ fields_base) end)
    |> update_at(:sent, Map.get(tracked_info, :sent_at, now()))
    |> update_at(:tracked, tracked_at)
  end

  @impl true
  # NOTE: duplicate variables in the pattern are matched
  def handle_call({:release, refid, opts}, _from, %{refid: refid} = state) do
    release_at = Keyword.get(opts, :ref_dt, now())

    state = update_at(state, :released, release_at) |> notify_if_requested(:ok)

    :ok = record_metrics(state)
    :ok = Alfred.Broom.Metrics.count(state)

    # :normal exit won't restart the linked process
    {:stop, :normal, :ok, state}
  end

  @impl true
  # NOTE: duplicate variables in the pattern are matched
  def handle_call({:tracked_info, refid, _opts}, _from, %{refid: refid} = state) do
    state.tracked_info |> reply(state)
  end

  @impl true
  def handle_info(:timeout, %{module: module} = state) do
    now = now()
    state = update_at(state, [:timeout, :released], now) |> notify_if_requested(:timeout)

    try do
      _ignored = module.broom_timeout(state)
    catch
      _, _ -> :ok
    end

    :ok = record_metrics(state)
    :ok = Alfred.Broom.Metrics.count(state)
    :ok = record_timeout(state)

    {:stop, :normal, state}
  end

  @doc false
  defmacro format_exception(kind, reason) do
    quote do
      ["\n", Exception.format(unquote(kind), unquote(reason), __STACKTRACE__)] |> IO.puts()

      {:failed, {unquote(kind), unquote(reason)}}
    end
  end

  @doc false
  def metrics(state), do: state

  @doc false
  def notify_if_requested(%{notify_pid: pid} = state, rc) do
    struct(state, rc: rc)
    |> tap(fn state -> if is_pid(pid), do: Process.send(pid, {Alfred, state}, []) end)
  end

  @doc false
  def server(refid), do: {:via, Registry, {@registry, refid}}

  # @doc false
  # def short_name({:via, Registry, {_, short_name}}), do: short_name

  @doc false
  def record_metrics(state) do
    %{opts: opts, module: module, at: at} = state

    [
      measurement: "command",
      tags: [module: module, name: opts[:name], cmd: opts[:cmd]],
      fields: [
        cmd_roundtrip_us: Timex.diff(at.released, at.tracked),
        cmd_total_us: Timex.diff(at.released, at.sent)
      ]
    ]
    |> Betty.write()

    :ok
  end

  @doc false
  def record_timeout(state) do
    %{module: module, opts: opts, refid: refid} = state

    name = opts[:name]

    [mutable: name, module: module, name: name, cmd: opts[:cmd], timeout: true, refid: refid]
    |> Betty.app_error_v2()

    :ok
  end

  @doc false
  def call(msg, refid) do
    server(refid) |> GenServer.call(msg)
  catch
    _kind, {:noproc, {GenServer, :call, _}} ->
      :not_tracked

    _kind, {:normal, {GenServer, :call, _}} ->
      :ok

    kind, reason ->
      {kind, reason} |> tap(fn x -> ["\n", inspect(x, pretty: true)] |> IO.puts() end)
      #  kind, reason -> format_exception(kind, reason)
  end

  @doc false
  def opts_final(module, opts), do: use_opts(module) |> consolidate_opts(opts)

  @doc false
  def opt(opts, :timeout_ms) do
    get_in(opts, [:cmd_opts, :timeout_ms]) || Keyword.get(opts, :timeout_ms, @timeout_ms_default)
  end

  @doc false
  def consolidate_opts(use_opts, opts) do
    opts_all = opts ++ use_opts

    Enum.reduce(opts_all, [], fn
      {:timeout_ms, ms}, acc -> Keyword.put_new(acc, :timeout_ms, ms)
      {:timeout_after, iso8601}, acc -> Keyword.put_new(acc, :timeout_ms, to_ms(iso8601))
      {:cmd_opts, cmd_opts}, acc -> merge_cmd_opts(acc, cmd_opts)
      {:ref_dt, at}, acc -> Keyword.put_new(acc, :ref_dt, at)
      {key, val}, acc -> Keyword.put_new(acc, key, val)
    end)
    |> Enum.sort()
  end

  @doc false
  def merge_cmd_opts(acc, more_cmd_opts) do
    priority_cmd_opts = Keyword.get(acc, :cmd_opts, [])
    merged = Keyword.merge(more_cmd_opts, priority_cmd_opts)

    Keyword.put(acc, :cmd_opts, merged)
  end

  @doc false
  def now, do: DateTime.utc_now()

  @doc false
  def notify?(opts), do: Keyword.get(opts, :cmd_opts, []) |> Keyword.get(:notify_when_released, false)

  @doc false
  def reply(rc, %__MODULE__{} = state), do: {:reply, rc, state}
  def reply(%__MODULE__{} = state, rc), do: {:reply, rc, state}

  @doc false
  def timeout_ms(%{at: %{tracked: at}, timeout_ms: timeout_ms}) do
    elapsed_ms = Timex.diff(now(), at, :milliseconds)

    if elapsed_ms > timeout_ms, do: 0, else: timeout_ms - elapsed_ms
  end

  @doc false
  def update_at(state, [_ | _] = keys, at) do
    Enum.reduce(keys, state, fn key, acc -> update_at(acc, key, at) end)
  end

  @at_keys [:sent, :tracked, :released, :timeout]
  def update_at(state, key, %DateTime{} = at) when key in @at_keys do
    struct(state, at: Map.put(state.at, key, at))
  end

  @doc false
  def to_ms(<<"PT"::binary, _rest::binary>> = iso8601) do
    Timex.Duration.parse!(iso8601) |> Timex.Duration.to_milliseconds(truncate: true)
  end
end
