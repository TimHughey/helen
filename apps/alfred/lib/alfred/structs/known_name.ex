defmodule Alfred.KnownName do
  defstruct name: "new name",
            mod: Alfred.Fake,
            mutable: false,
            seen_at: DateTime.utc_now(),
            ttl_ms: 30_000
end
