defmodule Alfred.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: __MODULE__, max_restarts: 10, max_seconds: 5]

    [{Alfred.Name.Supervisor, []}, {Alfred.Notify.Supervisor, []}, {Alfred.Broom.Supervisor, []}]
    |> Supervisor.start_link(opts)
  end
end
