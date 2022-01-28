defmodule Sally.Dispatch.Supervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @mqtt_connection Application.compile_env!(:sally, :mqtt_connection)

  @impl true
  def init(_inir_args) do
    children = [
      {Registry, [name: registry(), keys: :unique]},
      {Sally.Host.Dispatch, []},
      {Sally.Immutable.Dispatch, []},
      {Sally.Mutable.Dispatch, []},
      {Sally.Host.Instruct, []},
      {Tortoise.Connection, @mqtt_connection}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def registry, do: Sally.Dispatch.Registry
end
