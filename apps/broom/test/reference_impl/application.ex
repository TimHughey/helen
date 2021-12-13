defmodule Broom.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Broom.Repo, []},
      {Broom.Execute, [metrics_interval: "PT1M"]}
    ]

    opts = [strategy: :one_for_one, name: Broom.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
