defmodule Sally.Application do
  @moduledoc false

  require Logger

  use Application

  @mqtt_connection Application.compile_env!(:sally, :mqtt_connection)
  # @client_id Application.compile_env!(:sally, [:mqtt_connection, :client_id])
  # @client_opts Application.compile_env!(:sally, Sally.Mqtt.Client)

  @impl true
  def start(_type, _args) do
    children = [
      {Sally.Repo, []},
      {Tortoise.Connection, @mqtt_connection},
      {Sally.Payload, []},
      {Sally.Execute, []},
      {Sally.Host.Handler, []}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Sally.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
