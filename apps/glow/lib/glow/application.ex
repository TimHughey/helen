defmodule Glow.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [Glow]

    # start Glow.Application supervisor
    opts = [strategy: :one_for_one, max_restarts: 10, max_seconds: 10]
    Supervisor.start_link(children, opts)
  end
end
