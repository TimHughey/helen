defmodule Sally.Application do
  @moduledoc false

  require Logger

  use Application

  @mqtt_connection Application.compile_env!(:sally, :mqtt_connection)

  @impl true
  def start(_type, _args) do
    children = [
      {Sally.Repo, []},
      {Tortoise.Connection, @mqtt_connection},
      {Sally.Execute, []},
      {Sally.Immutable.Handler, []},
      {Sally.PulseWidth.Handler, []},
      {Sally.Host.Instruct, []},
      {Sally.Host.Handler, []}
    ]

    opts = [strategy: :one_for_one, name: Sally.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
