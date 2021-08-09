defmodule Alfred.KnownName do
  alias __MODULE__

  defstruct name: "unknown",
            callback_mod: Alfred.Unknown,
            mutable?: false,
            seen_at: DateTime.from_unix!(0, :microsecond),
            ttl_ms: 30_000,
            missing?: false

  @type t :: %__MODULE__{
          name: String.t(),
          callback_mod: module(),
          mutable?: boolean(),
          seen_at: DateTime.t(),
          ttl_ms: pos_integer(),
          missing?: boolean()
        }

  def detect_missing(%KnownName{} = kn, utc_now \\ &DateTime.utc_now/0) do
    ttl_dt = DateTime.add(kn.seen_at, kn.ttl_ms, :millisecond)
    now = utc_now.()

    if DateTime.compare(now, ttl_dt) == :gt, do: %KnownName{kn | missing?: true}, else: kn
  end

  def immutable?(%KnownName{} = kn), do: not kn.mutable?

  def missing?(%KnownName{} = kn), do: kn.missing?

  def new(name, mutable?, ttl_ms, callback_mod) do
    %KnownName{
      name: name,
      callback_mod: callback_mod,
      mutable?: mutable?,
      seen_at: DateTime.utc_now(),
      ttl_ms: ttl_ms
    }
  end

  def unknown(name), do: %KnownName{name: name}

  def unknown?(%KnownName{} = kn) do
    case kn do
      %KnownName{callback_mod: Alfred.Unknown} -> true
      _ -> false
    end
  end
end
