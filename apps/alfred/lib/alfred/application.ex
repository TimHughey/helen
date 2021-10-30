defmodule Alfred.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Alfred.{Names, Notify}

  @impl true
  def start(_type, _args) do
    children = [
      {Names.Server, []},
      {Notify.Server, []}
    ]

    opts = [strategy: :one_for_one, name: Alfred.Supervisor, max_restarts: 10, max_seconds: 5]
    Supervisor.start_link(children, opts)
  end
end
