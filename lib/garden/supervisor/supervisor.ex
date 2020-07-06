defmodule Garden.Supervisor do
  @moduledoc false

  use Supervisor

  @impl true
  def init(opts) do
    server_opts = [opts, server_mode: :active] |> List.flatten()

    Supervisor.init(
      [
        {Garden.Irrigation.Server, server_opts},
        {Garden.Lighting.Server, server_opts}
      ],
      strategy: :one_for_one
    )
  end

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def which_children do
    for {mod, pid, _, _} <- Supervisor.which_children(__MODULE__),
        reduce: %{} do
      acc -> acc |> put_in([mod], Process.info(pid))
    end
  end
end
