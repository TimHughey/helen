defmodule UI.Channel.Handler.Roost do
  @moduledoc false

  alias Phoenix.Socket
  alias UI.RoostView

  def add_status(resp \\ %{}), do: put_in(resp, [:status], RoostView.status())

  def click(payload, %{assigns: _assigns} = socket) do
    RoostView.button_click(payload, socket)
    |> add_status()
    |> reply()
  end

  def join(socket) do
    Socket.assign(socket, :live_update, false)
  end

  def page_loaded(socket) do
    add_status()
    |> reply(socket)
  end

  def reply(%{socket: %Socket{} = socket} = resp) do
    reply(Map.drop(resp, [:socket]), socket)
  end

  def reply(response, %Socket{} = socket), do: {:reply, {:roost, response}, socket}
  def reply(%Socket{} = socket, response), do: reply(response, socket)
end
