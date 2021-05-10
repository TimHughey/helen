defmodule Switch.Supervisor do
  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    alias Switch.DB.Command, as: Command
    alias Switch.Notify, as: Notify

    Supervisor.init([Notify, Command],
      strategy: :one_for_one,
      name: __MODULE__
    )
  end
end
