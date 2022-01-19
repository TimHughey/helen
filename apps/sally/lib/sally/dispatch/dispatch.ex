defmodule Sally.Dispatch do
  require Logger

  alias __MODULE__

  # @derive {Inspect, only: [:valid?, :subsystem, :category]}
  defstruct env: nil,
            subsystem: nil,
            category: nil,
            post_process?: false,
            ident: nil,
            filter_extra: [],
            payload: nil,
            data: nil,
            sent_at: nil,
            recv_at: nil,
            log: [],
            routed: :no,
            host: :not_loaded,
            txn_info: :none,
            results: %{},
            seen_list: [],
            final_at: nil,
            valid?: false,
            invalid_reason: "not processed"

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
          sent_at: DateTime.t() | nil,
          recv_at: DateTime.t() | nil,
          log: list(),
          routed: :no | :ok,
          host: Ecto.Schema.t() | nil,
          txn_info: :none | {:ok, map()} | {:error, map()},
          results: struct() | nil,
          seen_list: [binary(), ...],
          final_at: DateTime.t() | nil,
          valid?: boolean(),
          invalid_reason: String.t()
        }

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
  @spec accept(accept_tuple()) :: Dispatch.t()
  def accept({[env, ident, subsystem, category, extras], payload}) do
    %Dispatch{
      env: env,
      subsystem: subsystem,
      category: category,
      ident: ident,
      filter_extra: extras,
      payload: payload
    }
    |> preprocess()
  end

  def accumulate_post_process_results(acc, %Dispatch{} = dispatch) do
    results = Map.put_new(dispatch.results, :post_process, [])

    struct(dispatch, results: %{results | post_process: [acc] ++ results.post_process})
  end

  def check_txn(%Sally.Dispatch{} = dispatch) do
    case dispatch do
      # NOTE: filter out invalid Dispatch to avoid matching on valid? below
      %{valid?: false} -> dispatch
      %{txn_info: {:ok, %{host: host} = txn_info}} -> struct(dispatch, host: host, txn_info: txn_info)
      %{txn_info: {:ok, txn_info}} -> struct(dispatch, txn_info: txn_info)
      %{txn_info: {:error, txn_error}} -> invalid(dispatch, txn_error)
      %{txn_info: :none} -> dispatch
    end
  end

  def finalize(dispatch) do
    struct(dispatch, final_at: DateTime.utc_now())
    |> tap(fn dispatch -> log_if_invalid(dispatch) end)
  end

  @routing [host: Sally.Host.Handler, immut: Sally.Immutable.Handler, mut: Sally.Mutable.Handler]
  def handoff(%Sally.Dispatch{subsystem: subsystem} = dispatch) do
    msg_handler = Keyword.get(@routing, String.to_atom(subsystem), :unknown)

    pid = GenServer.whereis(msg_handler)

    cond do
      msg_handler == :unknown -> invalid(dispatch, "undefined routing: #{subsystem}")
      not is_pid(pid) -> invalid(dispatch, "no server: #{msg_handler}")
      true -> struct(dispatch, routed: GenServer.cast(pid, route_now(dispatch)))
    end
  end

  def invalid(%Dispatch{} = d, reason), do: struct(d, valid?: false, invalid_reason: reason)

  def load_host(%Dispatch{} = m) do
    if m.valid? do
      case Sally.Host.find_by_ident(m.ident) do
        %Sally.Host{authorized: true} = host ->
          %Dispatch{m | host: host}

        %Sally.Host{authorized: false} = host ->
          %Dispatch{m | host: host, valid?: false, invalid_reason: "host not authorized"}

        nil ->
          %Dispatch{m | valid?: false, invalid_reason: "unknown host"}
      end
    else
      m
    end
  end

  def new(fields), do: struct(Sally.Dispatch, fields)

  def preprocess(%Dispatch{} = m) do
    with %Dispatch{valid?: true} = m <- check_metadata(m),
         %Dispatch{valid?: true, data: data} = m <- unpack(m),
         %Dispatch{valid?: true} = m <- check_sent_time(m) do
      # transfer logging instructions from remote
      log = [msg: data[:log] || false] ++ m.log

      # prune data fields already consumed
      data = Map.drop(data, [:mtime, :log])

      %Dispatch{m | data: data, log: log, invalid_reason: "none"}
    else
      %Dispatch{valid?: false} = x -> x
    end
  end

  def route_now(dispatch), do: struct(dispatch, routed: :ok)

  def routed(%{routed: :ok, valid?: true} = dispatch, callback_mod) when is_atom(callback_mod) do
    [post_process?: function_exported?(callback_mod, :post_process, 1)]
    |> then(fn fields -> struct(dispatch, fields) end)
  end

  def routed(%{} = dispatch), do: invalid(dispatch, :routing_failed) |> finalize()

  def save_txn_info(txn_info, %Sally.Dispatch{} = dispatch), do: struct(dispatch, txn_info: txn_info)

  def unpack(%Dispatch{payload: payload} = m) do
    if is_bitstring(payload) do
      case Msgpax.unpack(payload) do
        {:ok, data} -> %Dispatch{m | valid?: true, data: atomize_keys(data), payload: :unpacked}
        {:error, e} -> invalid(m, e)
      end
    else
      invalid(m, "unknown payload")
    end
  end

  def valid(%{txn_info: %{} = txn_info} = dispatch), do: valid(dispatch, txn_info)

  def valid(%Dispatch{} = d, results \\ %{}) do
    struct(d, valid?: true, results: results, invalid_reason: :none)
  end

  # only atomze base map keys
  defp atomize_keys(x) when is_map(x) do
    for {k, v} <- x, into: %{} do
      if is_binary(k), do: {String.to_atom(k), v}, else: {k, v}
    end
  end

  @host_categories ["startup", "boot", "run", "ota", "log"]
  @subsystems ["immut", "mut"]
  defp check_metadata(%Dispatch{} = m) do
    case {m.subsystem, m.category} do
      {"host", cat} when cat in @host_categories -> valid(m)
      {subsystem, _cat} when subsystem in @subsystems -> valid(m) |> load_host()
      x -> invalid(m, "unknown subsystem/category: #{inspect(x)}")
    end
  end

  @variance_opt [Sally.Message.Handler, :mtime_variance_ms]
  @variance_ms Application.compile_env(:sally, @variance_opt, 10_000)

  defp check_sent_time(%Dispatch{data: data} = m) do
    recv_at = m.recv_at || DateTime.utc_now()
    sent_at = DateTime.from_unix!(data[:mtime] || 0, :millisecond)

    m = %Dispatch{m | recv_at: recv_at, sent_at: sent_at}
    ms_diff = DateTime.diff(recv_at, sent_at, :millisecond)

    cond do
      DateTime.compare(sent_at, DateTime.from_unix!(0)) == :eq -> invalid(m, "mtime is missing")
      ms_diff < @variance_ms * -1 -> invalid(m, "data is from the future #{ms_diff * -1}ms")
      ms_diff < 0 -> %Dispatch{m | sent_at: m.recv_at}
      ms_diff >= @variance_ms -> invalid(m, "data is #{ms_diff} old")
      true -> m
    end
  end

  defp log_if_invalid(%{valid?: valid?} = dispatch) do
    if valid? == false, do: Logger.warn(["\n", inspect(dispatch, pretty: true)]), else: :ok
  end
end
