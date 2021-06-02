defmodule Sally.MsgIn do
  require Logger

  @msg_old_ms Application.compile_env!(:sally, [Sally.MsgIn, :msg_old_ms])
  @routing Application.compile_env!(:sally, [Sally.MsgIn, :routing])

  alias __MODULE__

  defstruct payload: nil,
            env: nil,
            report?: nil,
            host: nil,
            category: nil,
            ident: nil,
            misc: nil,
            sent_at: nil,
            recv_at: nil,
            data: nil,
            roundtrip_ref: nil,
            log: [],
            valid?: false,
            invalid_reason: nil,
            faults: [],
            final_at: nil,
            routed: nil

  @type payload :: :unpacked | String.t()
  @type log :: [] | [msg: boolean()]

  @type t :: %__MODULE__{
          payload: payload,
          env: String.t(),
          report?: String.t(),
          host: String.t(),
          category: Types.msg_type(),
          ident: Types.device_or_remote_identifier(),
          misc: nil | String.t(),
          sent_at: %DateTime{},
          recv_at: %DateTime{},
          data: map(),
          roundtrip_ref: nil | String.t(),
          log: list(),
          valid?: boolean(),
          invalid_reason: Msgpax.UnpackError.t(),
          faults: [],
          final_at: DateTime.t(),
          routed: nil | :ok
        }

  def create(topic_filters, payload) when is_list(topic_filters) and is_bitstring(payload) do
    filters = Enum.zip([:env, :report, :host, :category, :ident, :misc], topic_filters)

    %MsgIn{
      payload: payload,
      env: filters[:env],
      report?: filters[:report] == "r",
      host: filters[:host],
      category: filters[:category],
      ident: filters[:ident],
      misc: filters[:misc],
      recv_at: DateTime.utc_now()
    }
    |> MsgIn.preprocess()
  end

  def handoff(%MsgIn{} = mi) do
    case mi do
      %MsgIn{valid?: true} = valid_msg -> route_msg(valid_msg)
      %MsgIn{valid?: false} -> mi
    end
    |> log_invalid_if_needed()
  end

  def preprocess(%MsgIn{} = mi) do
    with %MsgIn{valid?: true} = mi <- check_metadata(mi),
         %MsgIn{valid?: true, data: data} = mi <- unpack(mi),
         %MsgIn{valid?: true} = mi <- check_sent_time(mi) do
      # transfer logging instructions from remote
      log = [msg: data[:log] || false] ++ mi.log

      # capture the roundtrip ref if provided
      roundtrip_ref = data[:roundtrip_ref]

      # prune data fields already consumed
      data = Map.drop(data, [:mtime, :log, :roundtrip_ref])

      %MsgIn{mi | data: data, log: log, roundtrip_ref: roundtrip_ref}
    else
      %MsgIn{valid?: false} = x -> x
    end
  end

  def unpack(%MsgIn{payload: payload} = mi) do
    if is_bitstring(payload) do
      case Msgpax.unpack(payload) do
        {:ok, data} -> %MsgIn{mi | valid?: true, data: atomize_keys(data), payload: :unpacked}
        {:error, e} -> invalid(mi, e)
      end
    else
      invalid(mi, "unknown payload")
    end
  end

  # only atomize base map keys
  defp atomize_keys(x) when is_map(x) do
    for {k, v} <- x, into: %{} do
      if is_binary(k), do: {String.to_atom(k), v}, else: {k, v}
    end
  end

  defp check_metadata(%MsgIn{} = mi) do
    cond do
      mi.env not in ["dev", "test", "prod"] -> invalid(mi, "unknown env filter")
      not mi.report? -> invalid(mi, "report filter incorrect")
      not is_binary(mi.host) -> invalid(mi, "host filter missing")
      not is_binary(mi.category) -> invalid(mi, "category filter missing")
      not is_binary(mi.ident) -> invalid(mi, "ident filter missing")
      true -> %MsgIn{mi | valid?: true}
    end
  end

  defp check_sent_time(%MsgIn{data: data} = mi) do
    recv_at = mi.recv_at || DateTime.utc_now()
    sent_at = DateTime.from_unix!(data[:mtime] || 0, :millisecond)

    mi = %MsgIn{mi | recv_at: recv_at, sent_at: sent_at}

    cond do
      DateTime.compare(sent_at, DateTime.from_unix!(0)) == :eq -> invalid(mi, "mtime is missing")
      DateTime.compare(sent_at, recv_at) == :gt -> invalid(mi, "data is from the future")
      DateTime.diff(recv_at, sent_at, :millisecond) >= @msg_old_ms -> invalid(mi, "data is old")
      true -> mi
    end
  end

  defp invalid(%MsgIn{} = mi, reason), do: %MsgIn{mi | valid?: false, invalid_reason: reason}

  defp log_invalid_if_needed(mi) do
    if mi.valid? == false, do: Logger.warn(["invalid_msg:\n", inspect(mi, pretty: true)])

    mi
  end

  defp route_msg(%MsgIn{} = mi) do
    msg_server = @routing[String.to_atom(mi.category)]
    pid = GenServer.whereis(msg_server)

    cond do
      is_nil(msg_server) -> invalid(mi, "undefined routing: #{mi.category}")
      not is_pid(pid) -> invalid(mi, "no server: #{inspect(msg_server)}")
      true -> %MsgIn{mi | routed: GenServer.cast(msg_server, mi)}
    end
  end
end
