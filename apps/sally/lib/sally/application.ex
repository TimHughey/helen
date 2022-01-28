defmodule Sally.Application do
  @moduledoc false

  require Logger

  use Application

  @config_all Application.get_all_env(:sally)

  @impl true
  def start(_type, _args) do
    children = [
      {Sally.Config.Agent, @config_all},
      {Sally.Repo, []},
      {Sally.Command, []},
      {Sally.Dispatch.Supervisor, []}
    ]

    opts = [strategy: :one_for_one, name: Sally.Supervisor, max_restarts: 10, max_seconds: 5]
    Supervisor.start_link(children, opts)
  end
end
