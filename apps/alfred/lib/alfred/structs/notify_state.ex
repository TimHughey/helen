defmodule Alfred.NotifyServerState do
  defstruct registrations: %{}
end

defmodule Alfred.NotifyTo do
  defstruct name: "none",
            pid: nil,
            ref: nil,
            last_notify: DateTime.from_unix!(0),
            interval_ms: 60_000
end
