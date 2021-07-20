defmodule Alfred.KnownName do
  alias __MODULE__

  defstruct name: "unknown",
            callback_mod: Alfred.Fake,
            mutable?: false,
            seen_at: DateTime.from_unix!(0, :microsecond),
            ttl_ms: 30_000,
            missing?: true

  @type t :: %__MODULE__{
          name: String.t(),
          callback_mod: module(),
          mutable?: boolean(),
          seen_at: DateTime.t(),
          ttl_ms: pos_integer(),
          missing?: boolean()
        }

  def detect_missing(%KnownName{} = kn) do
    utc_now = DateTime.utc_now()
    ttl_dt = DateTime.add(utc_now, kn.ttl_ms * -1, :millisecond)

    if DateTime.compare(utc_now, ttl_dt) != :gt, do: %KnownName{kn | missing?: true}, else: kn
  end

  def missing(%KnownName{} = kn), do: %KnownName{kn | missing?: true}
  def missing?(%KnownName{} = kn), do: kn.missing?

  def new(name, mutable?, ttl_ms, callback_mod) do
    %KnownName{
      name: name,
      callback_mod: callback_mod,
      mutable?: mutable?,
      seen_at: DateTime.utc_now(),
      ttl_ms: ttl_ms,
      missing?: false
    }
  end
end
