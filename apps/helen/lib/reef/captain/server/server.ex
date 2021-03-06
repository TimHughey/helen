defmodule Reef.Captain.Server do
  @moduledoc """
  Orchestration of Reef Activities (e.g. salt mix, cleaning)
  """

  use GenServer, shutdown: 2000
  use Helen.Worker.Logic

  ##
  ## GenServer Start and Initialization
  ##

  @doc false
  @impl true
  def init(args) do
    alias Reef.Captain.Config

    Logic.init_server(__MODULE__, args, %{config: Config.config(:latest)})
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end
end
