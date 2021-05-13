defmodule Alfred.KnownName do
  defstruct name: "new name",
            callback_mod: Alfred.Fake,
            mutable: false,
            seen_at: DateTime.utc_now(),
            ttl_ms: 30_000

  @type t :: %__MODULE__{
          name: String.t(),
          callback_mod: module(),
          mutable: boolean(),
          seen_at: DateTime.t(),
          ttl_ms: pos_integer()
        }
end
