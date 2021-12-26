defmodule Glow.Application do
  @moduledoc false

  use Application

  # alias Glow.Instance

  @impl true
  def start(_type, _args) do
    children = [Glow]
    #   {Carol.Server, Instance.start_args(:front_chandelier)},
    #   {Carol.Server, Instance.start_args(:front_evergreen)},
    #   {Carol.Server, Instance.start_args(:front_red_maple)},
    #   {Carol.Server, Instance.start_args(:greenhouse)}
    # ]

    # start Glow.Application supervisor
    opts = [strategy: :one_for_one, max_restarts: 10, max_seconds: 10]
    Supervisor.start_link(children, opts)
  end
end
