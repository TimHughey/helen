defmodule Reef.FirstMate.Server do
  @moduledoc """
  Provides support to Reef.FirstMate.Server, specificially reef clean mode.
  """

  use Timex

  use GenServer, restart: :transient, shutdown: 5000
  use Helen.Worker.Logic

  ##
  ## GenServer init and start
  ##

  @doc false
  @impl true
  def init(args) do
    import Reef.FirstMate.Opts, only: [parsed: 0]

    # just in case we were passed a map?!?
    args = Enum.into(args, [])
    opts = parsed()

    Logic.init_server(__MODULE__, args, opts)
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end
end
