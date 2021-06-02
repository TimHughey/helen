defmodule Sally.PulseWidth.Supervisor do
  use Supervisor

  alias Sally.PulseWidth

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {PulseWidth.Payload, []},
      {PulseWidth.MsgHandler, []},
      {PulseWidth.Execute, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
