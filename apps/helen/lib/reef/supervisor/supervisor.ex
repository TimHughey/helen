defmodule Reef.Supervisor do
  @moduledoc false

  use Supervisor

  @impl true
  def init(opts) do
    alias Reef.{DisplayTank, MixTank}

    Supervisor.init(
      [
        {DisplayTank.Temp, DisplayTank.Temp.default_opts()},
        {Reef.DisplayTank.Ato, []},
        {MixTank.Temp, MixTank.Temp.default_opts()},
        {Reef.MixTank.Pump, opts},
        {Reef.MixTank.Air, opts},
        {Reef.MixTank.Rodi, opts},
        {Reef.Captain.Server, opts},
        {Reef.FirstMate.Server, opts}
      ],
      strategy: :one_for_one
    )
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
