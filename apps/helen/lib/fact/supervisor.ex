defmodule Fact.Supervisor do
  @moduledoc false

  require Logger
  use Supervisor

  alias Fact.Influx

  @impl true
  def init(_args) do
    Supervisor.init([Influx.child_spec()],
      strategy: :rest_for_one,
      name: Fact.Supervisor
    )
  end

  def start_link(args \\ [log: [init: false, init_args: false]])
      when is_list(args) do
    Supervisor.start_link(__MODULE__, Enum.into(args, %{}), name: __MODULE__)
  end
end
