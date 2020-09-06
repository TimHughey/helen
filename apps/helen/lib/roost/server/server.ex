defmodule Roost.Server do
  @moduledoc false

  # @compile {:no_warn_undefined, PulseWidth}

  alias PulseWidth
  use Timex

  use GenServer, restart: :transient, shutdown: 5000
  use Helen.Worker.Logic

  ##
  ## GenServer init and start
  ##

  @impl true
  def init(args) do
    import Roost.Opts, only: [parsed: 0]

    # just in case we were passed a map?!?
    args = Enum.into(args, [])
    opts = parsed()

    state = %{
      module: __MODULE__,
      server: %{
        mode: args[:server_mode] || :active,
        standby_reason: :none,
        faults: %{}
      },
      opts: opts,
      timeouts: %{last: :never, count: 0},
      token: nil,
      token_at: nil
    }

    # should the server start?
    if state[:server][:mode] == :standby do
      :ignore
    else
      {:ok, state, {:continue, :bootstrap}}
    end
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end
end
