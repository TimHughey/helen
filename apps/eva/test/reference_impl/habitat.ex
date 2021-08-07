defmodule Eva.Habitat do
  alias __MODULE__
  use Eva, name: Habitat, id: Habitat, restart: :permanent, shutdown: 1000
end

defmodule Eva.RefImpl.AutoOff do
  alias __MODULE__
  use Eva, name: AutoOff, id: AutoOff, restart: :permanent, shutdown: 1000
end
