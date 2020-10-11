defmodule Reef.Captain.Server do
  @moduledoc """
  Orchestration of Reef Activities (e.g. salt mix, cleaning)
  """

  use GenServer, restart: :transient, shutdown: 7000
  use Helen.Worker.Logic

  # alias Reef.FirstMate.Server, as: FirstMate
  # alias Reef.MixTank
  # alias Reef.MixTank.{Air, Pump, Rodi}

  ##
  ## GenServer Start and Initialization
  ##

  @doc false
  @impl true
  def init(args) do
    import Reef.Captain.Config, only: [config: 1]

    Logic.init_server(__MODULE__, args, %{config: config(:latest)})
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end
end
