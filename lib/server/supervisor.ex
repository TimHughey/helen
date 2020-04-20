defmodule Helen.Supervisor do
  @moduledoc """
  Helen Globally Exposed API Supervisor
  """
  @moduledoc since: "0.0.4"

  require Logger
  use Supervisor

  #
  ## GenServer Callbacks
  #

  @doc """
  init() callback
  """

  @impl true
  @doc since: "0.0.4"
  def init(args) do
    servers_to_start(args)
    |> Supervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start the Helen Supervisor
  """
  @doc since: "0.0.4"
  def start_link(args) when is_list(args) do
    Supervisor.start_link(__MODULE__, Enum.into(args, %{}),
      name: {:global, :helen_supervisor}
    )
  end

  #
  ## Private
  #

  defp servers_to_start(args) when is_map(args) do
    [
      {Helen.Server, Map.put_new(args, :start_workers, true)}
    ]
  end
end
