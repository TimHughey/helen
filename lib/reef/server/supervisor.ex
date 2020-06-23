defmodule Reef.Supervisor do
  @moduledoc false

  use Supervisor

  @impl true
  def init(opts) do
    Supervisor.init(
      [
        {Reef.MixTank.Pump, opts},
        {Reef.MixTank.Air, opts},
        {Reef.MixTank.Rodi, opts},
        {Reef.Temp.DisplayTank, []},
        {Reef.Temp.MixTank, [mode: :standby]},
        {Reef.MixTank.Fill, [mode: :standby]}
      ],
      strategy: :one_for_one
    )
  end

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
end
