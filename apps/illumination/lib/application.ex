defmodule Illumination.Application do
  @moduledoc false

  require Logger

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Greenhouse, Greenhouse.start_args()}
    ]

    opts = [strategy: :one_for_one, name: Illumination.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
