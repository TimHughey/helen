defmodule Roost.Supervisor do
  @moduledoc false

  use Supervisor

  @impl true
  def init(_opts) do
    Supervisor.init([{Roost, []}], strategy: :one_for_one)
  end

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def which_children do
    for {mod, pid, _, _} <- Supervisor.which_children(__MODULE__),
        reduce: [] do
      acc -> Keyword.put(acc, mod, pid)
    end
  end
end
