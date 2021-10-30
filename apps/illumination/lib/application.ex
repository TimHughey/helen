defmodule Illumination.Application do
  @moduledoc false

  require Logger

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Greenhouse, Greenhouse.start_args()},
      {FrontChandelier, FrontChandelier.start_args()},
      {FrontRedMaple, FrontRedMaple.start_args()},
      {FrontEvergreen, FrontEvergreen.start_args()}
    ]

    opts = [
      strategy: :one_for_one,
      name: Illumination.Supervisor,
      max_restarts: 10,
      max_seconds: 5
    ]

    Supervisor.start_link(children, opts)
  end
end
