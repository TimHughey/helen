defmodule PulseWidth.Supervisor do
  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    alias PulseWidth.DB.Command, as: Command

    Supervisor.init([Command],
      strategy: :one_for_one,
      name: __MODULE__
    )
  end
end
