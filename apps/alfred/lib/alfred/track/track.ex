defmodule Alfred.Track do
  @moduledoc false

  require Logger
  use GenServer

  @registry Alfred.Track.Supervisor.registry()

  @timeout_ms_default 3300

  @at_map %{sent: nil, tracked: nil, complete: nil, released: nil, timeout: nil}

  defstruct refid: nil,
            tracked_info: nil,
            at: @at_map,
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

  @type status_opt() :: :complete

  @callback make_refid() :: String.t()
  @callback now() :: DateTime.t()
  @callback release(refid :: String.t(), opts :: list()) :: :ok
  @callback track(map(), opts :: list()) :: Track.t()
  @callback track(status_opt(), schema :: map(), DateTime.t()) :: :ok
  @callback track_now?(what :: map() | struct(), opts :: list) :: boolean()
  @callback track_timeout(Alfred.Track.t()) :: any()
  @callback tracked_info(refid :: String.t() | pid) :: any()

  # coveralls-ignore-start
  defmacro __using__(use_opts) do
    quote location: :keep, bind_quoted: [use_opts: use_opts] do
      # NOTE: capture use opts for Alfred.Track
      Alfred.Track.put_attribute(__MODULE__, use_opts)
      @behaviour Alfred.Track

      def make_refid, do: Alfred.Track.make_refid()

      @doc false
      def now, do: Alfred.Track.now()
      def release(what, opts), do: Alfred.Track.release(what, __MODULE__, opts)

      # def track(exec_result, opts), do: Alfred.Track.track(exec_result, __MODULE__, opts)
      def track(what, opts), do: Alfred.Track.track(what, __MODULE__, opts)
      def track(status, refid, at), do: Alfred.Track.track({status, refid}, __MODULE__, at)
      def track_now?(_what, _opts), do: true
      defoverridable track_now?: 2

      def tracked_info(what), do: Alfred.Track.tracked_info(what, __MODULE__)
    end
  end

  @mod_attribute :alfred_track_use_opts

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
  def use_opts(module), do: get_attribute(module)

  def make_refid do
    Ecto.UUID.generate() |> String.split("-") |> Enum.take(4) |> Enum.join("-")
  end

  def release(<<_::binary>> = refid, module, opts) do
    {:release, refid, opts_final(module, opts)} |> call(refid)
  end

  # def track(%{refid: refid} = exec_result, module, opts) do
  #   opts = opts_final(module, opts)
  #
  #   [tracked_info: exec_result, module: module, opts: opts, caller_pid: self()]
  #   |> then(fn args -> GenServer.start_link(__MODULE__, args, name: server(refid)) end)
  #   |> munge_start_link_rc()
  # end

  def track(%{refid: _, track: _} = item, module, opts) do
    if module.track_now?(item, opts), do: track_now(item, module, opts), else: item
  end

  @status [:complete]
  def track({status, <<_::binary>> = refid}, module, %DateTime{} = at) when status in @status do
    {:status, refid, status, at, opts_final(module, [])} |> call(refid)
  end

  def tracked?(refid) do
    case Registry.lookup(@registry, refid) do
      [{pid, _}] when is_pid(pid) -> true
      _ -> false
    end
  end

  def tracked_info(pid) when is_pid(pid) do
    GenServer.call(pid, {:tracked_info, []})
  end

  def tracked_info(refid, module) do
    {:tracked_info, refid, opts_final(module, [])} |> call(refid)
  end

  def track_now(%{refid: refid, track: _} = item, module, opts) do
    opts = opts_final(module, opts)
    args = [tracked_info: item, module: module, opts: opts, caller_pid: self()]
    server_opts = [name: server(refid)]

    rc = GenServer.start_link(__MODULE__, args, server_opts)

    Map.put(item, :track, munge_start_link_rc(rc))
  end

  ## GenServer

  @impl true
  def init(opts) do
    {caller_pid, opts_rest} = Keyword.pop(opts, :caller_pid)

    Process.link(caller_pid)
    state = make_state(caller_pid, opts_rest)

    :ok = Alfred.Track.Metrics.count(state)
    _ = Process.send_after(self(), :timeout, timeout_ms(state))

    {:ok, state}
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

    # NOTE: ensure complete at is set.
    # update_at/3 won't override previous value when passed a list of keys
    at_list = [released: release_at, complete: release_at]
    state = update_at(state, at_list) |> notify_if_requested(:ok)

    :ok = record_metrics(state)
    :ok = Alfred.Track.Metrics.count(state)

    # :normal exit won't restart the linked process
    {:stop, :normal, :ok, state}
  end

  @impl true
  # NOTE: duplicate variables in the pattern are matched
  def handle_call({:status, refid, status, at, _opts}, _from, %{refid: refid} = state) do
    update_at(state, status, at)
    |> reply(:ok)
  end

  @impl true
  # NOTE: duplicate variables in the pattern are matched
  def handle_call({:tracked_info, refid, _opts}, _from, %{refid: refid} = state) do
    state.tracked_info |> reply(state)
  end

  @impl true
  def handle_call({:tracked_info, _opts}, _from, state) do
    state.tracked_info |> reply(state)
  end

  @impl true
  def handle_info(:timeout, %{module: module} = state) do
    now = now()
    state = update_at(state, [:timeout, :released], now) |> notify_if_requested(:timeout)

    try do
      _ignored = module.track_timeout(state)
    catch
      _, _ -> :ok
    end

    :ok = record_metrics(state)
    :ok = Alfred.Track.Metrics.count(state)
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

  @doc false
  def record_metrics(state) do
    %{opts: opts, tracked_info: info, at: at} = state

    name = opts[:name]
    cmd = if(is_struct(info), do: info.cmd, else: opts[:cmd])

    tags = [mutable: name, name: name, cmd: cmd, release: true]

    fields = [
      track_us: safe_diff_dt(at.tracked, at.sent),
      roundtrip_us: safe_diff_dt(at.complete, at.sent),
      release_us: safe_diff_dt(at.released, at.complete),
      timeout_us: safe_diff_dt(at.timeout, at.sent)
    ]

    # NOTE: Betty.runtime_metric/3 will extract module from state
    Betty.runtime_metric(state, tags, fields)

    :ok
  end

  @doc false
  def record_timeout(state) do
    %{module: module, opts: opts, tracked_info: info} = state

    name = opts[:name]
    cmd = if(is_struct(info), do: info.cmd, else: info[:cmd])

    [mutable: name, module: module, name: name, cmd: cmd, timeout: true]
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
    default = Keyword.get(opts, :timeout_ms, @timeout_ms_default)
    get_in(opts, [:cmd_opts, :timeout_ms]) || default
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

  def munge_start_link_rc(rc) do
    case rc do
      {:ok, pid} when is_pid(pid) -> rc
      {:error, {:already_started, pid}} when is_pid(pid) -> {:tracked, pid}
    end
  end

  @doc false
  def now, do: DateTime.utc_now()

  @doc false
  def notify?(opts), do: Keyword.get(opts, :cmd_opts, []) |> Keyword.get(:notify_when_released, false)

  @doc false
  def reply(rc, %__MODULE__{} = state), do: {:reply, rc, state}
  def reply(%__MODULE__{} = state, rc), do: {:reply, rc, state}

  @doc false
  def safe_diff_dt(later_dt, early_dt) do
    Timex.diff(later_dt, early_dt, :microseconds)
  catch
    _, _ -> nil
  end

  @doc false
  def timeout_ms(%{at: %{tracked: at}, timeout_ms: timeout_ms}) do
    elapsed_ms = Timex.diff(now(), at, :milliseconds)

    if elapsed_ms > timeout_ms, do: 0, else: timeout_ms - elapsed_ms
  end

  @doc false
  def to_ms(<<"PT"::binary, _rest::binary>> = iso8601) do
    Timex.Duration.parse!(iso8601)
    |> Timex.Duration.to_milliseconds(truncate: true)
  end

  @at_keys Map.keys(@at_map)

  @doc false
  def update_at(state, [_ | _] = kv_pairs) do
    updates = Enum.into(kv_pairs, %{})

    # NOTE: existing at values never replaced
    Map.merge(updates, state.at, fn
      _key, lhs, nil -> lhs
      _key, _lhs, rhs -> rhs
    end)
    |> then(fn at_map -> struct(state, at: at_map) end)
  end

  @doc false
  def update_at(state, [_ | _] = keys, at) do
    # NOTE: never override a previously set at key
    keys = Enum.filter(keys, fn key -> Map.get(state.at, key) == nil end)

    Enum.reduce(keys, state, fn key, acc -> update_at(acc, key, at) end)
  end

  def update_at(state, key, %DateTime{} = at) when key in @at_keys do
    struct(state, at: Map.put(state.at, key, at))
  end
end
