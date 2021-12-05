defmodule Carol.RefImpl do
  use Carol, restart: :transient, shutdown: 10_000
end
