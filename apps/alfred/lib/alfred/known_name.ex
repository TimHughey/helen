defmodule Alfred.KnownName do
  alias __MODULE__

  defstruct name: "unknown",
            callback_mod: Alfred.NoCallback,
            server_name: Alfred.NoServer,
            mutable?: false,
            seen_at: DateTime.from_unix!(0, :microsecond),
            ttl_ms: 30_000,
            missing?: false

  @type t :: %__MODULE__{
          name: String.t(),
          callback_mod: module(),
          server_name: atom(),
          mutable?: boolean(),
          seen_at: DateTime.t(),
          ttl_ms: pos_integer(),
          missing?: boolean()
        }

  def detect_missing(%KnownName{} = kn, utc_now \\ &DateTime.utc_now/0) do
    ttl_dt = DateTime.add(kn.seen_at, kn.ttl_ms, :millisecond)
    now = utc_now.()

    %KnownName{kn | missing?: DateTime.compare(now, ttl_dt) == :gt}

    # if DateTime.compare(now, ttl_dt) == :gt, do: %KnownName{kn | missing?: true}, else: kn
  end

  def immutable?(%KnownName{} = kn), do: not kn.mutable?

  def missing?(%KnownName{} = kn), do: kn.missing?

  def new(args) when is_map(args) or is_list(args) do
    struct(KnownName, args)
  end

  def new(name, mutable?, ttl_ms, callback_mod) do
    %KnownName{
      name: name,
      callback_mod: callback_mod,
      mutable?: mutable?,
      seen_at: DateTime.utc_now(),
      ttl_ms: ttl_ms
    }
  end

  def unknown(name), do: %KnownName{name: name, missing?: true}

  def unknown?(%KnownName{} = kn) do
    case kn do
      %KnownName{callback_mod: Alfred.Unknown} -> true
      _ -> false
    end
  end
end
