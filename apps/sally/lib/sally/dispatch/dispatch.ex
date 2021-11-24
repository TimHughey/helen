defmodule Sally.Dispatch do
  require Logger

  alias __MODULE__
  alias Sally.{Host, Immutable, Mutable}
  # alias Sally.TypesI

  @msg_mtime_variance_ms Application.compile_env!(:sally, [Sally.Message.Handler, :msg_mtime_variance_ms])

  # @derive {Inspect, only: [:valid?, :subsystem, :category]}
  defstruct env: nil,
            subsystem: nil,
            category: nil,
            ident: nil,
            filter_extra: [],
            payload: nil,
            data: nil,
            sent_at: nil,
            recv_at: nil,
            log: [],
            routed: :no,
            host: nil,
            results: %{},
            seen_list: [],
            final_at: nil,
            valid?: false,
            invalid_reason: "metadata not checked"

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
          ident: host_ident(),
          filter_extra: extras(),
          payload: payload(),
          data: map() | nil,
          sent_at: DateTime.t() | nil,
          recv_at: DateTime.t() | nil,
          log: list(),
          routed: :no | :ok,
          host: Ecto.Schema.t() | nil,
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

  def finalize(%Dispatch{} = m) do
    %Dispatch{m | final_at: DateTime.utc_now()}
    |> log_invalid_if_needed()
  end

  def handoff(%Dispatch{} = m) do
    case m do
      %Dispatch{valid?: true} = valid_msg -> route_msg(valid_msg)
      %Dispatch{valid?: false} -> m
    end
    |> log_invalid_if_needed()
  end

  def invalid(%Dispatch{} = d, reason) do
    struct(d, valid?: false, invalid_reason: reason)
  end

  def load_host(%Dispatch{} = m) do
    if m.valid? do
      case Host.find_by_ident(m.ident) do
        %Host{authorized: true} = host ->
          %Dispatch{m | host: host}

        %Host{authorized: false} = host ->
          %Dispatch{m | host: host, valid?: false, invalid_reason: "host not authorized"}

        nil ->
          %Dispatch{m | valid?: false, invalid_reason: "unknown host"}
      end
    else
      m
    end
  end

  def preprocess(%Dispatch{} = m) do
    with %Dispatch{valid?: true} = m <- check_metadata(m),
         %Dispatch{valid?: true, data: data} = m <- unpack(m),
         %Dispatch{valid?: true} = m <- check_sent_time(m) do
      # transfer logging instructions from remote
      log = [msg: data[:log] || false] ++ m.log

      # prune data fields already consumed
      data = Map.drop(data, [:mtime, :log])

      %Dispatch{m | data: data, log: log, invalid_reason: nil}
    else
      %Dispatch{valid?: false} = x -> x
    end
  end

  def save_seen_list(seen_list, %Dispatch{} = m) do
    %Dispatch{m | seen_list: seen_list}
  end

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

  defp check_sent_time(%Dispatch{data: data} = m) do
    recv_at = m.recv_at || DateTime.utc_now()
    sent_at = DateTime.from_unix!(data[:mtime] || 0, :millisecond)

    m = %Dispatch{m | recv_at: recv_at, sent_at: sent_at}
    ms_diff = DateTime.diff(recv_at, sent_at, :millisecond)

    cond do
      DateTime.compare(sent_at, DateTime.from_unix!(0)) == :eq -> invalid(m, "mtime is missing")
      ms_diff < @msg_mtime_variance_ms * -1 -> invalid(m, "data is from the future #{ms_diff * -1}ms")
      ms_diff < 0 -> %Dispatch{m | sent_at: m.recv_at}
      ms_diff >= @msg_mtime_variance_ms -> invalid(m, "data is #{ms_diff} old")
      true -> m
    end
  end

  defp log_invalid_if_needed(m) do
    if m.valid? == false, do: Logger.warn(["invalid_msg:\n", inspect(m, pretty: true)])

    m
  end

  @routing [host: Host.Handler, immut: Immutable.Handler, mut: Mutable.Handler]
  defp route_msg(%Dispatch{} = m) do
    msg_handler_module = get_in(@routing, [String.to_atom(m.subsystem)])

    pid = GenServer.whereis(msg_handler_module)

    cond do
      is_nil(msg_handler_module) -> invalid(m, "undefined routing: #{m.subsystem}")
      not is_pid(pid) -> invalid(m, "no server: #{inspect(msg_handler_module)}")
      true -> %Dispatch{m | routed: GenServer.cast(msg_handler_module, m)}
    end
  end
end
