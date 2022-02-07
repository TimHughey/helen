defmodule Alfred.Notify.Supervisor do
  # Automatically defines child_spec/1
  use Supervisor

  @impl true
  def init(_init_arg) do
    [{Registry, [name: registry(), keys: :duplicate]}]
    |> Supervisor.init(strategy: :one_for_one)
  end

  def registry, do: Alfred.Notify.Registry

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
end
