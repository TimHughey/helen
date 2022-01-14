defmodule Alfred.Broom.Supervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init([registry]) do
    children = [
      {Alfred.Broom.Metrics, []},
      {Registry, [name: registry, keys: :unique]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
