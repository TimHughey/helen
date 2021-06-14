defmodule Sally.Host.Message do
  require Logger

  alias __MODULE__, as: Msg
  alias Sally.Host.Reply
  alias Sally.Types

  # TODO: revisit configuration of :msg_old_ms
  @msg_old_ms Application.compile_env!(:sally, [Sally.Message.Handler, :msg_old_ms])

  defstruct env: nil,
            category: nil,
            ident: nil,
            payload: nil,
            data: nil,
            sent_at: nil,
            recv_at: nil,
            log: [],
            routed: :no,
            host: nil,
            reply: nil,
            final_at: nil,
            valid?: false,
            invalid_reason: "metadata not checked"

  # "boot", "run", "ota", "log"
  @type category() :: String.t()

  @type t :: %__MODULE__{
          env: Types.msg_env(),
          category: category(),
          ident: String.t(),
          payload: Types.payload(),
          data: map() | nil,
          sent_at: DateTime.t() | nil,
          recv_at: DateTime.t() | nil,
          log: list(),
          routed: :no | :ok,
          host: Ecto.Schema.t() | nil,
          reply: Reply.t(),
          valid?: boolean(),
          invalid_reason: String.t()
        }

  def add_reply(%Reply{} = reply, %Msg{} = msg) do
    %Msg{msg | reply: reply}
  end

  def accept({[env, ident, category], payload}) do
    %Msg{env: env, category: category, ident: ident, payload: payload} |> preprocess()
  end

  def handoff(%Msg{} = m) do
    case m do
      %Msg{valid?: true} = valid_msg -> route_msg(valid_msg)
      %Msg{valid?: false} -> m
    end
    |> log_invalid_if_needed()
  end

  def invalid(%Msg{} = m, reason), do: %Msg{m | valid?: false, invalid_reason: reason}

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

  @known_categories ["boot", "run", "ota", "log"]
  defp check_metadata(%Msg{} = m) do
    case m.category do
      cat when cat in @known_categories -> %Msg{m | valid?: true}
      _ -> invalid(m, "unknown category: #{m.category}")
    end
  end

  defp check_sent_time(%Msg{data: data} = m) do
    recv_at = m.recv_at || DateTime.utc_now()
    sent_at = DateTime.from_unix!(data[:mtime] || 0, :millisecond)

    m = %Msg{m | recv_at: recv_at, sent_at: sent_at}
    ms_diff = DateTime.diff(recv_at, sent_at, :millisecond)

    cond do
      DateTime.compare(sent_at, DateTime.from_unix!(0)) == :eq -> invalid(m, "mtime is missing")
      ms_diff < -100 -> invalid(m, "data is from #{ms_diff} in the future")
      ms_diff < 0 -> %Msg{m | sent_at: m.recv_at}
      ms_diff >= @msg_old_ms -> invalid(m, "data is #{ms_diff} old")
      true -> m
    end
  end

  defp log_invalid_if_needed(m) do
    if m.valid? == false, do: Logger.warn(["invalid_msg:\n", inspect(m, pretty: true)])

    m
  end

  # @route_to Sally.Host.Handler
  defp route_msg(%Msg{} = m) do
    mod_parts = __MODULE__ |> Module.split()
    mod_base = Enum.take(mod_parts, length(mod_parts) - 1)
    msg_handler_module = (mod_base ++ [Handler]) |> Module.concat()
    pid = GenServer.whereis(msg_handler_module)

    cond do
      is_nil(msg_handler_module) -> invalid(m, "undefined routing: #{m.category}")
      not is_pid(pid) -> invalid(m, "no server: #{inspect(msg_handler_module)}")
      true -> %Msg{m | routed: GenServer.cast(msg_handler_module, m)}
    end
  end
end
