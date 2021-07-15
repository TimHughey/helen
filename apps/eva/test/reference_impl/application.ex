defmodule Eva.Application do
  @moduledoc false

  use Application

  @habitat_opts Application.compile_env!(:eva, Eva.Habitat)

  @impl true
  def start(_type, _args) do
    children = [
      {Eva.Habitat, @habitat_opts}
    ]

    opts = [strategy: :one_for_one, name: Eva.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
