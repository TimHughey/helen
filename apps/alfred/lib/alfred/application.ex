defmodule Alfred.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Alfred.{Names, Notify}

  @registries [broom: Alfred.Broom.Registry, name: Alfred.Name.Registry, notify: Alfred.Notify.Registry]

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, [name: @registries[:name], keys: :unique]},
      {Alfred.Notify.Supervisor, []},
      {Registry, [name: @registries[:notify], keys: :duplicate]},
      {Alfred.Broom.Supervisor, [registry(:broom)]},
      {Names.Server, []},
      {Notify.Server, []}
    ]

    opts = [strategy: :one_for_one, name: Alfred.Supervisor, max_restarts: 10, max_seconds: 5]
    Supervisor.start_link(children, opts)
  end

  def registry(what), do: @registries[what]
end
