defmodule Eva.Habitat do
  alias __MODULE__
  use Eva, name: Habitat, id: Habitat, restart: :permanent, shutdown: 1000
end
