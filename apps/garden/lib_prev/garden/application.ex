defmodule Garden.Application do
  @moduledoc false

  require Logger

  use Application

  # @lights Application.compile_env!(:garden, Lights)

  def start(_type, _args) do
    # children = [{Lights.Server, @lights}]
    children = []

    opts = [strategy: :one_for_one, name: Garden.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
