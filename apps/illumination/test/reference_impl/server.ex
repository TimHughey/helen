defmodule Illumination.RefImpl do
  use Illumination, restart: :transient, shutdown: 10_000
end
