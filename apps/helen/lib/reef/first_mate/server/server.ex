defmodule Reef.FirstMate.Server do
  @moduledoc """
  Provides support to Reef.FirstMate.Server, specificially reef clean mode.
  """

  use Timex

  use GenServer, restart: :transient, shutdown: 5000
  use Helen.Worker.Logic

  alias Reef.FirstMate.Config

  ##
  ## GenServer init and start
  ##

  @doc false
  @impl true
  def init(args) do
    Logic.init_server(__MODULE__, args, %{config: config(:latest)})
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def config(what \\ :latest, config_txt \\ ""),
    do: Config.config(what, config_txt)
end
