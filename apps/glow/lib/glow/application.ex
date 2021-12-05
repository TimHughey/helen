defmodule Glow.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: Glow.Worker.start_link(arg)
      # {Glow.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Glow.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
