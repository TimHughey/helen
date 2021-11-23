defmodule Alfred.KnownName do
  alias __MODULE__

  defstruct name: "unknown",
            callback: {:unset, nil},
            mutable?: false,
            seen_at: DateTime.from_unix!(0, :microsecond),
            ttl_ms: 30_000,
            missing?: false,
            valid?: true

  @type callback_tuple() :: {:server, atom()} | {:module, module()} | mfa()
  @type t :: %__MODULE__{
          name: String.t(),
          callback: callback_tuple(),
          mutable?: boolean(),
          seen_at: DateTime.t(),
          ttl_ms: pos_integer(),
          missing?: boolean(),
          valid?: boolean()
        }

  def detect_missing(%KnownName{} = kn, utc_now \\ nil) do
    if kn.valid? do
      utc_now = if(is_nil(utc_now), do: DateTime.utc_now(), else: utc_now)
      ttl_dt = DateTime.add(kn.seen_at, kn.ttl_ms, :millisecond)

      %KnownName{kn | missing?: Timex.after?(utc_now, ttl_dt)}
    else
      %KnownName{kn | missing?: true}
    end
  end

  def unknown(name) do
    %KnownName{name: name, missing?: true, valid?: false} |> validate()
  end

  def validate(%KnownName{name: name} = kn) when is_binary(name) do
    for key <- [:callback, :seen_at, :ttl_ms], reduce: kn do
      %KnownName{valid?: false} = kn_acc ->
        kn_acc

      %KnownName{valid?: true} = kn_acc ->
        case key do
          :callback -> validate_callback(kn_acc)
          :seen_at -> validate_seen_at(kn_acc)
          :ttl_ms -> validate_ttl_ms(kn_acc)
        end
    end
    |> detect_missing()
  end

  ##
  ## Private
  ##

  defp invalid(%KnownName{} = kn), do: %KnownName{kn | valid?: false}

  defp validate_callback(%KnownName{callback: cb} = kn) do
    case cb do
      {what, x} when what in [:server, :module] and is_atom(x) -> kn
      func when is_function(func) -> kn
      _ -> invalid(kn)
    end
  end

  defp validate_seen_at(%KnownName{seen_at: seen_at} = kn) do
    case seen_at do
      %DateTime{} -> kn
      _ -> invalid(kn)
    end
  end

  defp validate_ttl_ms(%KnownName{ttl_ms: ttl_ms} = kn) do
    case ttl_ms do
      x when is_integer(x) and x > 0 -> kn
      _ -> invalid(kn)
    end
  end
end
