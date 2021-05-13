defmodule Alfred.ControlServerState do
  defstruct timeout: %{last: nil, ms: 1000}, token: make_ref()
end
