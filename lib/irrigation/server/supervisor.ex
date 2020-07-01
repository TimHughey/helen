defmodule Irrigation.Supervisor do
  @moduledoc false

  use Supervisor

  @impl true
  def init(opts) do
    server_opts = [opts, server_mode: :active] |> List.flatten()

    Supervisor.init([{Irrigation.Server, server_opts}],
      strategy: :one_for_one
    )
  end

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
end
