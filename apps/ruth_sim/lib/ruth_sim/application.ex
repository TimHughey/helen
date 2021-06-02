defmodule RuthSim.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  require Logger
  use Application

  @mqtt_connection Application.compile_env!(:ruth_sim, :mqtt_connection)
  @topic Application.compile_env!(:ruth_sim, :topic)
  @client_id Application.compile_env!(:ruth_sim, [:mqtt_connection, :client_id])
  @handler_opts Application.compile_env!(:ruth_sim, RuthSim.Mqtt.Handler)

  @impl true
  def start(_type, _args) do
    children = [
      {Tortoise.Connection, make_conn_opts()},
      {RuthSim.InboundMsg.Server, nil},
      {RuthSim.Mqtt.Client, client_opts()},
      {PwmKeeper, nil},
      {SwitchKeeper, nil},
      {SensorKeeper, nil}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: RuthSim.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def client_opts do
    [@topic, client_id: @client_id] |> List.flatten()
  end

  def connection_opts do
    [@mqtt_connection] |> List.flatten()
  end

  def make_conn_opts do
    handler = {RuthSim.Mqtt.Handler, @handler_opts}

    @mqtt_connection
    |> put_in([:handler], handler)
    |> put_in([:options], topic: @topic)
  end

  def pretty(msg, x), do: "#{msg}: #{inspect(x, pretty: true)}"
end
