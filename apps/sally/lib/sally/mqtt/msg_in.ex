defmodule Sally.MsgIn do
  require Logger

  alias __MODULE__

  defstruct payload: nil,
            env: nil,
            host: nil,
            type: nil,
            at: nil,
            data: nil,
            roundtrip_ref: nil,
            log: [],
            valid?: nil,
            invalid_reason: nil

  @type payload :: :unpacked | String.t()
  @type log :: [] | [msg: boolean()]

  @type t :: %__MODULE__{
          payload: payload,
          env: String.t(),
          host: String.t(),
          type: String.t(),
          at: %DateTime{},
          data: map(),
          roundtrip_ref: nil | String.t(),
          log: list(),
          valid?: boolean(),
          invalid_reason: Msgpax.UnpackError.t()
        }

  def preprocess(%MsgIn{} = mi) do
    with %MsgIn{valid?: true} = mi <- unpack(mi),
         %MsgIn{valid?: true, data: data} = mi <- check_metadata(mi) do
      # transfer logging instructions from remote
      log = [msg: data[:log] || false] ++ mi.log

      # capture the roundtrip ref if provided
      roundtrip_ref = data[:roundtrip_ref]

      # prune data fields already consumed
      data = Map.drop(data, [:mtime, :log, :roundtrip_ref])

      %MsgIn{mi | data: data, log: log, roundtrip_ref: roundtrip_ref}
    else
      %MsgIn{valid?: false} = x -> log_invalid(x)
    end
  end

  defp check_metadata(%MsgIn{data: data} = mi) do
    mtime_min = System.os_time(:second) - 5

    case data do
      %{mtime: x} when x < mtime_min -> invalid(mi, "data is old")
      %{mtime: _} -> mi
      _ -> invalid(mi, "mtime key missing")
    end
  end

  # (1 of 2) payload is a bitstring, attempt to unpack it
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

  # don't attempt to atomize structs
  defp atomize_keys(%{} = x) when is_struct(x), do: x

  defp atomize_keys(%{} = map) do
    map
    |> Enum.map(fn {k, v} -> {String.to_atom(k), atomize_keys(v)} end)
    |> Enum.into(%{})
  end

  # Walk the list and atomize the keys of
  # of any map members
  defp atomize_keys([head | rest]) do
    [atomize_keys(head) | atomize_keys(rest)]
  end

  defp atomize_keys(not_a_map) do
    not_a_map
  end

  defp invalid(%MsgIn{} = mi, reason), do: %MsgIn{mi | valid?: false, invalid_reason: reason}

  defp log_invalid(mi) do
    Logger.debug(["invalid_msg:\n", inspect(mi, pretty: true)])
    mi
  end
end
