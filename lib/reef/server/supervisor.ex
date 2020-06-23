defmodule Reef.Supervisor do
  @moduledoc false

  use Supervisor

  @impl true
  def init(opts) do
    Supervisor.init(
      [
        {Reef.DisplayTank.Temp, []},
        {Reef.DisplayTank.Ato, []},
        {Reef.MixTank.Temp, [mode: :standby]},
        {Reef.MixTank.Pump, opts},
        {Reef.MixTank.Air, opts},
        {Reef.MixTank.Rodi, opts}
      ],
      strategy: :one_for_one
    )
  end

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
end
