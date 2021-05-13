defmodule Alfred.ControlServerState do
  defstruct timeout: %{last: nil, ms: 1000}, token: nil
end
