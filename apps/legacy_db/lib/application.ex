defmodule LegacyDb.Application do
  @moduledoc false

  require Logger

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {LegacyDb.Repo, []}
    ]

    opts = [strategy: :one_for_one, name: LegacyDb.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
