defmodule Rena.HoldCmd.Server do
  require Logger
  use GenServer

  alias __MODULE__
  alias Alfred.ExecResult
  alias Alfred.Notify.Memo
  alias Broom.TrackerEntry
  alias Rena.HoldCmd.State

  @impl true
  def init(args) when is_list(args) or is_map(args) do
    {:ok, State.new(args), {:continue, :bootstrap}}
  end

  def start_link(start_args) do
    server_name = start_args[:name] || start_args[:server_name]
    server_opts = [name: start_args[:name]]
    start_args = start_args ++ [server_name: server_name]

    GenServer.start_link(Server, start_args, server_opts)
  end

  @impl true
  def handle_continue(:bootstrap, %State{} = s) do
    {:ok, ticket} = s.alfred.notify_register(name: s.equipment, frequency: :all, link: true)

    State.save_equipment(s, ticket)
    |> noreply()

    # NOTE: at this point the server is running and no further actions occur until an
    #       equipment notification is received
  end

  defp noreply(%State{} = s), do: {:noreply, s}
end
