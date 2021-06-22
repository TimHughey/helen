defmodule Sally.Dispatch do
  require Logger

  alias __MODULE__, as: Msg
  alias Sally.Host
  alias Sally.Types

  @msg_mtime_variance_ms Application.compile_env!(:sally, [Sally.Message.Handler, :msg_mtime_variance_ms])

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
            final_at: nil,
            valid?: false,
            invalid_reason: "metadata not checked"

  # "host", "pwm"
  @type subsystem() :: String.t()

  # "boot", "run", "ota", "log"
  @type category() :: String.t()

  @type t :: %__MODULE__{
          env: Types.msg_env(),
          subsystem: subsystem(),
          category: category(),
          ident: String.t(),
          filter_extra: list(),
          payload: Types.payload(),
          data: map() | nil,
          sent_at: DateTime.t() | nil,
          recv_at: DateTime.t() | nil,
          log: list(),
          routed: :no | :ok,
          host: Ecto.Schema.t() | nil,
          valid?: boolean(),
          invalid_reason: String.t()
        }

  def accept({[env, ident, subsystem, category, extras], payload}) do
    %Msg{
      env: env,
      subsystem: subsystem,
      category: category,
      ident: ident,
      filter_extra: extras,
      payload: payload
    }
    |> preprocess()
  end

  def handoff(%Msg{} = m) do
    case m do
      %Msg{valid?: true} = valid_msg -> route_msg(valid_msg)
      %Msg{valid?: false} -> m
    end
    |> log_invalid_if_needed()
  end

  def invalid(%Msg{} = m, reason), do: %Msg{m | valid?: false, invalid_reason: reason}

  def load_host(%Msg{} = m) do
    if m.valid? do
      case Host.find_by_ident(m.ident) do
        %Host{authorized: true} = host ->
          %Msg{m | host: host}

        %Host{authorized: false} = host ->
          %Msg{m | host: host, valid?: false, invalid_reason: "host not authorized"}

        nil ->
          %Msg{m | valid?: false, invalid_reason: "unknown host"}
      end
    else
      m
    end
  end

  def preprocess(%Msg{} = m) do
    with %Msg{valid?: true} = m <- check_metadata(m),
         %Msg{valid?: true, data: data} = m <- unpack(m),
         %Msg{valid?: true} = m <- check_sent_time(m) do
      # transfer logging instructions from remote
      log = [msg: data[:log] || false] ++ m.log

      # prune data fields already consumed
      data = Map.drop(data, [:mtime, :log])

      %Msg{m | data: data, log: log, invalid_reason: nil}
    else
      %Msg{valid?: false} = x -> x
    end
  end

  def unpack(%Msg{payload: payload} = m) do
    if is_bitstring(payload) do
      case Msgpax.unpack(payload) do
        {:ok, data} -> %Msg{m | valid?: true, data: atomize_keys(data), payload: :unpacked}
        {:error, e} -> invalid(m, e)
      end
    else
      invalid(m, "unknown payload")
    end
  end

  # only atomze base map keys
  defp atomize_keys(x) when is_map(x) do
    for {k, v} <- x, into: %{} do
      if is_binary(k), do: {String.to_atom(k), v}, else: {k, v}
    end
  end

  @known_host_categories ["startup", "boot", "run", "ota", "log", "pwm"]
  defp check_metadata(%Msg{} = m) do
    case {m.subsystem, m.category} do
      {"host", cat} when cat in @known_host_categories -> %Msg{m | valid?: true}
      {"pwm", _cat} -> %Msg{m | valid?: true} |> load_host()
      x -> invalid(m, "unknown subsystem/category: #{inspect(x)}")
    end
  end

  defp check_sent_time(%Msg{data: data} = m) do
    recv_at = m.recv_at || DateTime.utc_now()
    sent_at = DateTime.from_unix!(data[:mtime] || 0, :millisecond)

    m = %Msg{m | recv_at: recv_at, sent_at: sent_at}
    ms_diff = DateTime.diff(recv_at, sent_at, :millisecond)

    cond do
      DateTime.compare(sent_at, DateTime.from_unix!(0)) == :eq -> invalid(m, "mtime is missing")
      ms_diff < @msg_mtime_variance_ms * -1 -> invalid(m, "data is from the future #{ms_diff * -1}ms")
      ms_diff < 0 -> %Msg{m | sent_at: m.recv_at}
      ms_diff >= @msg_mtime_variance_ms -> invalid(m, "data is #{ms_diff} old")
      true -> m
    end
  end

  defp log_invalid_if_needed(m) do
    if m.valid? == false, do: Logger.warn(["invalid_msg:\n", inspect(m, pretty: true)])

    m
  end

  @routing [
    host: Sally.Host.Handler,
    pwm: Sally.PulseWidth.Handler
  ]
  defp route_msg(%Msg{} = m) do
    # mod_parts = __MODULE__ |> Module.split()
    # mod_base = Enum.take(mod_parts, length(mod_parts) - 1)
    # msg_handler_module = (mod_base ++ [Handler]) |> Module.concat()

    msg_handler_module = get_in(@routing, [String.to_atom(m.subsystem)])

    pid = GenServer.whereis(msg_handler_module)

    cond do
      is_nil(msg_handler_module) -> invalid(m, "undefined routing: #{m.subsystem}")
      not is_pid(pid) -> invalid(m, "no server: #{inspect(msg_handler_module)}")
      true -> %Msg{m | routed: GenServer.cast(msg_handler_module, m)}
    end
  end
end
